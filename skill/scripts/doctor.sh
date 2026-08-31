#!/usr/bin/env bash
# scripts/doctor.sh — simple-wiki 馆藏健康状态上报 (设计: .tmp/design-wiki-doctor.md v10 §4)
#
# 用法: bash doctor.sh [--detail]
# 输出: 头条层 KEY=VALUE (机器解析, 按首个 = 分割); --detail 追加名单层 KEY: value (按首个 ": " 分割)。
# 诊断与告警走 stderr。exit 0 = 脚本正常 (含 NEED_INIT=true), 非零 = 脚本自身故障。
# 契约要点:
#   - NEED_INIT 首位短路: 目录不存在或缺骨架件时仅输出 NEED_INIT=true + WIKI_ROOT 两行
#   - 实算 = 全文件含 frontmatter, 经 calculation-token.sh 直接调用 (单一真源)
#   - frontmatter 顶层键 = 行首顶格; 值剥行内注释 (` #` 起) + trim
#   - 阈值: WIKI_PAGE_LIMIT (默认 8k) / WIKI_INDEX_LIMIT (默认 32k), 上限语义 (>)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETAIL=0
[[ "${1:-}" == "--detail" ]] && DETAIL=1

# --- 根解析: 守卫阶梯 (§4, 单一规范源) ------------------------------------
TOPLEVEL="$(git rev-parse --show-toplevel 2>/dev/null || true)"

resolve_root() {
  local given="${1:-}"
  local root=""
  if [[ -n "$given" ]]; then
    root="$given"
    # 归一化: 相对值以 CWD 锚定 (字符串级, 目录不存在亦安全)
    if [[ "$root" != /* ]]; then root="$PWD/$root"; fi
    # 去尾部斜杠 (保留根 /)
    while [[ "$root" != "/" && "$root" == */ ]]; do root="${root%/}"; done
    # 目录存在时附加物理解析
    if [[ -d "$root" ]]; then root="$(cd "$root" && pwd -P)"; fi
  elif [[ -d "$PWD/docs/simple-wiki" ]]; then
    root="$PWD/docs/simple-wiki"
  elif [[ -n "$TOPLEVEL" && "$TOPLEVEL" != "$PWD" && -d "$TOPLEVEL/docs/simple-wiki" ]]; then
    printf 'doctor: 重定向至 git toplevel %s\n' "$TOPLEVEL" >&2
    root="$TOPLEVEL/docs/simple-wiki"
  elif [[ -n "$TOPLEVEL" && "$TOPLEVEL" != "$PWD" ]]; then
    printf 'doctor: 重定向至 git toplevel %s\n' "$TOPLEVEL" >&2
    root="$TOPLEVEL/docs/simple-wiki"
  else
    local marker_found=0
    local m
    for m in AGENTS.md CLAUDE.md package.json pyproject.toml go.mod Cargo.toml mise.toml .mise.toml; do
      if [[ -e "$PWD/$m" ]]; then marker_found=1; break; fi
    done
    if [[ $marker_found -eq 0 ]]; then
      printf 'doctor: CWD 不像工作区根 (非 git 目录且无项目标记), 建议核对位置或显式设置 WIKI_ROOT\n' >&2
    fi
    root="$PWD/docs/simple-wiki"
  fi
  printf '%s' "$root"
}

WIKI_ROOT_RESOLVED="$(resolve_root "${WIKI_ROOT:-}")"
PAGE_LIMIT="${WIKI_PAGE_LIMIT:-8}"
INDEX_LIMIT="${WIKI_INDEX_LIMIT:-32}"

# --- 骨架件判定 → 首位短路 ------------------------------------------------
SKELETON_MISSING=0
if [[ ! -d "$WIKI_ROOT_RESOLVED" ]]; then
  SKELETON_MISSING=1
else
  for f in raw wiki LOG.md SCHEMA.md LLM_WIKI.md LINT.md; do
    if [[ ! -e "$WIKI_ROOT_RESOLVED/$f" ]]; then SKELETON_MISSING=1; break; fi
  done
  [[ -e "$WIKI_ROOT_RESOLVED/wiki/INDEX.md" ]] || SKELETON_MISSING=1
fi

if [[ $SKELETON_MISSING -eq 1 ]]; then
  printf 'NEED_INIT=true\n'
  printf 'WIKI_ROOT=%s\n' "$WIKI_ROOT_RESOLVED"
  exit 0
fi

# --- 工具函数 ---------------------------------------------------------------
# fm_top_value <file> <key>: 取 frontmatter 顶层键值 (剥行内注释 + trim); 未找到输出空
fm_top_value() {
  awk -v k="$2" '
    NR==1 { if ($0 != "---") exit; infm=1; next }
    infm && /^---[[:space:]]*$/ { exit }
    infm && /^[[:space:]]/ { next }
    infm && index($0, ":") > 0 {
      pos = index($0, ":")
      if (substr($0, 1, pos-1) == k) {
        val = substr($0, pos+1)
        c = index(val, " #")
        if (c > 0) val = substr(val, 1, c-1)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
        print val
        exit
      }
    }
  ' "$1" 2>/dev/null || true
}

# has_fm_block <file>: 首行为 --- 且存在闭合 ---
has_fm_block() {
  awk 'NR==1 { if ($0 != "---") exit 1; next } /^---[[:space:]]*$/ { found=1; exit 0 } END { if (!found) exit 1 }' "$1" 2>/dev/null
}

# actual_k <file>: calculation-token.sh 实算, 输出 k 与 token (tab 分隔)
actual_k() {
  local out
  out="$(bash "$SCRIPT_DIR/calculation-token.sh" "$1")"
  local t k
  t="$(printf '%s\n' "$out" | sed -n 's/^tokens=//p')"
  k="$(printf '%s\n' "$out" | sed -n 's/^context=//p')"
  printf '%s\t%s' "$k" "$t"
}

RAW_COUNT=0; RAW_PENDING=0; RAW_PENDING_EVID=0; RAW_INVALID_FM=0
PAGE_COUNT=0; PAGE_OVERSIZED=0; CONTEXT_DRIFT=0; XLINK_DANGLING=0; XLINK_RAW=0
INDEX_ROWS=0; INDEX_UNLISTED=0; INDEX_DANGLING=0; INDEX_CONTEXT=0
LINT_BODY=0; LINT_ESCALATE=0; LINT_PARSE="ok"
D_P=""; D_PE=""; D_NF=""; D_IFM=""; D_OS=""; D_DR=""; D_XD=""; D_XR=""; D_IU=""; D_ID=""; D_LU=""; D_LS=""

# --- raw/ 检查 ---------------------------------------------------------------
RAW_COUNT="$(find "$WIKI_ROOT_RESOLVED/raw" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')"

while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  name="$(basename "$f")"
  if [[ "$name" != *.md ]]; then continue; fi
  if ! head -n 1 "$f" | grep -q '^---$'; then
    RAW_INVALID_FM=$((RAW_INVALID_FM+1))
    D_IFM="${D_IFM}NO_FRONTMATTER: ${name}
"
    continue
  fi
  if ! has_fm_block "$f"; then
    RAW_INVALID_FM=$((RAW_INVALID_FM+1))
    D_IFM="${D_IFM}INVALID_FM: ${name} (unclosed block)
"
    continue
  fi
  cls="$(fm_top_value "$f" class)"
  ing="$(fm_top_value "$f" ingested)"
  bad=""
  if [[ -z "$cls" && -z "$ing" && "$(fm_top_value "$f" title)" == "$(fm_top_value "$f" title)" ]]; then :; fi
  if [[ -z "$cls" ]]; then bad="missing class key"; fi
  if [[ -z "$ing" ]]; then bad="${bad:+$bad; }missing ingested key"; fi
  if [[ -n "$cls" && "$cls" != "material" && "$cls" != "evidence" ]]; then bad="${bad:+$bad; }class not in enum"; fi
  if [[ -n "$ing" && "$ing" != "true" && "$ing" != "false" ]]; then bad="${bad:+$bad; }ingested not bool"; fi
  if [[ -n "$bad" ]]; then
    RAW_INVALID_FM=$((RAW_INVALID_FM+1))
    D_IFM="${D_IFM}INVALID_FM: ${name} (${bad})
"
    continue
  fi
  if [[ "$ing" == "false" ]]; then
    if [[ "$cls" == "material" ]]; then
      RAW_PENDING=$((RAW_PENDING+1))
      D_P="${D_P}PENDING: ${name}
"
    else
      RAW_PENDING_EVID=$((RAW_PENDING_EVID+1))
      D_PE="${D_PE}PENDING_EVIDENCE: ${name}
"
    fi
  fi
done < <(find "$WIKI_ROOT_RESOLVED/raw" -maxdepth 1 -type f -name '*.md' 2>/dev/null | sort)

# --- wiki/ 页检查 ------------------------------------------------------------
shopt -s nullglob
WIKI_FILES=()
for f in "$WIKI_ROOT_RESOLVED/wiki"/*.md; do
  name="$(basename "$f")"
  [[ "$name" == "INDEX.md" ]] && continue
  WIKI_FILES+=("$f")
done
shopt -u nullglob
PAGE_COUNT=${#WIKI_FILES[@]}

# 页断链扫描: 目标分类 (../raw/ → XLINK_RAW; 同目录 .md → XLINK_DANGLING; 其余声明放弃)
scan_page_links() {
  local f="$1" src="$2"
  grep -oE '\[[^]]*\]\([^)]+\)' "$f" 2>/dev/null | sed 's/^\[[^]]*\](//; s/)$//' | while IFS= read -r target; do
    target="${target%%[[:space:]]*}"                # 剥 "title" 尾部
    target="${target%%#*}"                          # 剥锚点
    case "$target" in
      http://*|https://*|mailto:*|'') continue ;;
    esac
    target="${target#./}"
    case "$target" in
      ../raw/*.md)
        if [[ ! -f "$WIKI_ROOT_RESOLVED/raw/$(basename "$target")" ]]; then
          printf 'XRAW\t%s\t%s\n' "$src" "$target"
        fi
        ;;
      *.md)
        if [[ "$target" == */* ]]; then continue; fi   # 非同目录相对形态: 声明放弃
        if [[ ! -f "$WIKI_ROOT_RESOLVED/wiki/$target" ]]; then
          printf 'XD\t%s\t%s\n' "$src" "$target"
        fi
        ;;
    esac
  done
}

# frontmatter sources 条目 (inline 与块式; 相对库根)
scan_sources() {
  local f="$1" src="$2"
  awk -v src="$src" '
    NR==1 { if ($0=="---") { in_fm=1; next } else exit }
    in_fm && /^---[[:space:]]*$/ { exit }
    in_fm && /^sources:/ {
      val=$0
      sub(/^sources:[[:space:]]*/, "", val)
      if (val ~ /^\[/) {                          # inline 列表
        gsub(/^\[|\]$/, "", val)
        n=split(val, items, ",")
        for (i=1;i<=n;i++) emit(items[i])
        srcs_done=1; next
      } else if (val ~ /^-/) {                    # 同行块式首项
        emit(val); in_block=1; next
      } else { in_block=1; next }                 # 块式, 条目在后续行
    }
    in_fm && in_block && /^[-[:space:]]/ && !/^sources:/ {
      if ($0 ~ /^[[:space:]]*-/) { emit($0) } else { in_block=0 }
    }
    in_fm && !/^[-[:space:]]/ { in_block=0 }
    function emit(s,  t) {
      sub(/^[[:space:]]*-[[:space:]]*/, "", s)
      sub(/^#.*$/, "", s); sub(/[[:space:]]#.*$/, "", s)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
      if (s != "" && s !~ /\.md$/) s = s ".md"
      if (s != "" && s !~ /^raw\//) s = "raw/" s
      if (s != "") print "XSRC\t" src "\t" s
    }
  ' "$f" 2>/dev/null
}

LINK_RESULTS=""
for f in "${WIKI_FILES[@]}"; do
  name="$(basename "$f")"

  # 实算与 drift
  read -r ak at <<<"$(actual_k "$f")"
  if (( ak > PAGE_LIMIT )); then
    PAGE_OVERSIZED=$((PAGE_OVERSIZED+1))
    D_OS="${D_OS}OVERSIZED: ${name} (${ak}k)
"
  fi
  declared="$(fm_top_value "$f" context)"
  if [[ -n "$declared" && "$declared" =~ ^[0-9]+$ && "$declared" != "$ak" ]]; then
    CONTEXT_DRIFT=$((CONTEXT_DRIFT+1))
    D_DR="${D_DR}DRIFT: ${name} (declared ${declared}k, actual ${ak}k)
"
  fi

  LINK_RESULTS="${LINK_RESULTS}$(scan_page_links "$f" "$name")
$(scan_sources "$f" "$name")
"
done

while IFS=$'\t' read -r kind src target; do
  [[ -z "$kind" ]] && continue
  if [[ "$kind" == "XD" ]]; then
    XLINK_DANGLING=$((XLINK_DANGLING+1))
    D_XD="${D_XD}XLINK_DANGLING: ${src} -> ${target}
"
  elif [[ "$kind" == "XRAW" ]]; then
    XLINK_RAW=$((XLINK_RAW+1))
    D_XR="${D_XR}XLINK_RAW: ${src} (link) -> ${target}
"
  elif [[ "$kind" == "XSRC" ]]; then
    if [[ ! -f "$WIKI_ROOT_RESOLVED/$target" ]]; then
      XLINK_RAW=$((XLINK_RAW+1))
      D_XR="${D_XR}XLINK_RAW: ${src} (sources) -> ${target}
"
    fi
  fi
done <<<"$LINK_RESULTS"

# --- INDEX 检查 --------------------------------------------------------------
INDEX_FILE="$WIKI_ROOT_RESOLVED/wiki/INDEX.md"
INDEX_TARGETS=""
if [[ -f "$INDEX_FILE" ]]; then
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    INDEX_ROWS=$((INDEX_ROWS+1))
    tgt="$(printf '%s\n' "$line" | sed -n 's/.*](\([^)]*\)).*/\1/p' | sed 's/#.*$//; s/^\.\///')"
    INDEX_TARGETS="${INDEX_TARGETS}${tgt}
"
  done < <(grep -E '^- \[' "$INDEX_FILE" || true)
  read -r ik it <<<"$(actual_k "$INDEX_FILE")"
  INDEX_CONTEXT="$ik"
fi

# INDEX_DANGLING: 条目行目标不存在
while IFS= read -r tgt; do
  [[ -z "$tgt" ]] && continue
  if [[ ! -f "$WIKI_ROOT_RESOLVED/wiki/$tgt" ]]; then
    INDEX_DANGLING=$((INDEX_DANGLING+1))
    D_ID="${D_ID}INDEX_DANGLING: ${tgt}
"
  fi
done <<<"$INDEX_TARGETS"

# INDEX_UNLISTED: 页无对应条目
for f in "${WIKI_FILES[@]}"; do
  name="$(basename "$f")"
  if ! grep -qF "](${name})" "$INDEX_FILE" 2>/dev/null; then
    INDEX_UNLISTED=$((INDEX_UNLISTED+1))
    D_IU="${D_IU}INDEX_UNLISTED: ${name}
"
  fi
done

# --- LINT 解析 ---------------------------------------------------------------
LINT_FILE="$WIKI_ROOT_RESOLVED/LINT.md"
SEP_COUNT="$(grep -c '^## ESCALATE$' "$LINT_FILE" 2>/dev/null || true)"
[[ -z "$SEP_COUNT" ]] && SEP_COUNT=0
LINT_TYPES_OUT=""
if [[ "$SEP_COUNT" -ne 1 ]]; then
  LINT_PARSE="dirty"
  if [[ "$SEP_COUNT" -eq 0 ]]; then
    D_LS="LINT_STRUCTURE: 分隔符缺失
"
  else
    D_LS="LINT_STRUCTURE: 分隔符出现 ${SEP_COUNT} 次
"
  fi
  # 无法可靠分区: body/escalate 计数按全文 - 行近似 (标记 dirty 后计数不可信)
  LINT_BODY="$(grep -c '^- ' "$LINT_FILE" 2>/dev/null || true)"
  [[ -z "$LINT_BODY" ]] && LINT_BODY=0
else
  lint_parse_results="$(awk '
    BEGIN { sep=0; body=0; esc=0; dirty=0 }
    /^## ESCALATE$/ { sep=1; next }
    /^- / {
      n = split($0, cols, "|")
      if (n >= 3) {
        t = cols[2]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", t)
        if (t=="contradiction"||t=="stale"||t=="orphan"||t=="index-drift"||t=="other") {
          if (sep==0) { body++; types[t]++ } else { esc++ }
          next
        }
      }
      dirty=1
    }
    END {
      printf "%d\t%d\t%d\t", body, esc, dirty
      first=1
      for (k in types) { if (!first) printf ","; printf "%s:%d", k, types[k]; first=0 }
      printf "\n"
    }
  ' "$LINT_FILE")"
  IFS=$'\t' read -r LINT_BODY LINT_ESCALATE LINT_DIRTY LINT_TYPES_OUT <<<"$lint_parse_results"
  if [[ "$LINT_DIRTY" == "1" ]]; then
    LINT_PARSE="dirty"
    D_LU="$(awk '
      /^## ESCALATE$/ { sep=1 }
      /^- / {
        n = split($0, cols, "|")
        ok = 0
        if (n >= 3) {
          t = cols[2]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", t)
          if (t=="contradiction"||t=="stale"||t=="orphan"||t=="index-drift"||t=="other") ok=1
        }
        if (!ok) {
          line=$0; if (length(line)>80) line=substr(line,1,80) "..."
          printf "LINT_UNPARSED: %s\n", line
        }
      }
    ' "$LINT_FILE")"
  fi
fi

# --- 输出 --------------------------------------------------------------------
printf 'NEED_INIT=false\n'
printf 'WIKI_ROOT=%s\n' "$WIKI_ROOT_RESOLVED"
printf 'RAW_COUNT=%s\n' "$RAW_COUNT"
printf 'RAW_PENDING=%s\n' "$RAW_PENDING"
printf 'RAW_PENDING_EVIDENCE=%s\n' "$RAW_PENDING_EVID"
printf 'RAW_INVALID_FM=%s\n' "$RAW_INVALID_FM"
printf 'PAGE_COUNT=%s\n' "$PAGE_COUNT"
printf 'PAGE_OVERSIZED=%s\n' "$PAGE_OVERSIZED"
printf 'CONTEXT_DRIFT=%s\n' "$CONTEXT_DRIFT"
printf 'XLINK_DANGLING=%s\n' "$XLINK_DANGLING"
printf 'XLINK_RAW=%s\n' "$XLINK_RAW"
printf 'INDEX_ROWS=%s\n' "$INDEX_ROWS"
printf 'INDEX_UNLISTED=%s\n' "$INDEX_UNLISTED"
printf 'INDEX_DANGLING=%s\n' "$INDEX_DANGLING"
printf 'INDEX_CONTEXT=%s\n' "$INDEX_CONTEXT"
printf 'LINT_BODY=%s\n' "$LINT_BODY"
printf 'LINT_ESCALATE=%s\n' "$LINT_ESCALATE"
printf 'LINT_TYPES=%s\n' "$LINT_TYPES_OUT"
printf 'LINT_PARSE=%s\n' "$LINT_PARSE"
if (( INDEX_CONTEXT > INDEX_LIMIT )); then
  printf 'doctor: INDEX_CONTEXT %sk 超过上限 %sk (WIKI_INDEX_LIMIT), 建议与用户讨论收纳\n' "$INDEX_CONTEXT" "$INDEX_LIMIT" >&2
fi

if [[ $DETAIL -eq 1 ]]; then
  printf '%b' "$D_P" "$D_PE" "$D_NF" "$D_IFM" "$D_OS" "$D_DR" "$D_XD" "$D_XR" "$D_IU" "$D_ID" "$D_LU" "$D_LS"
fi
