#!/usr/bin/env bash
# scripts/context-stats.sh — 阅读清单预算器 (设计: .tmp/design-wiki-doctor.md v10 §5)
#
# 用法: bash context-stats.sh <page.md> [...] | --topic <主题名>
# 输出: WIKI_ROOT / READ_PAGES / READ_CONTEXT (k, ceil 显示) / SWARM_ADVISE (token 总和 ≥ 64000)
# 契约要点:
#   - 逐页经 calculation-token.sh 实算 (全文件含 frontmatter, 单一真源), 先求 token 总和再换算 k
#   - 不读 INDEX 声明值; 预算基于真值
#   - 根解析共享 doctor 的守卫阶梯
#   - 全有或全无: 任一页缺失 → stderr 报错 exit 1

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SWARM_LIMIT="${WIKI_SWARM_LIMIT:-64}"

# --- 根解析: 与 doctor.sh 相同的守卫阶梯 ------------------------------------
TOPLEVEL="$(git rev-parse --show-toplevel 2>/dev/null || true)"

resolve_root() {
  local given="${1:-}"
  local root=""
  if [[ -n "$given" ]]; then
    root="$given"
    if [[ "$root" != /* ]]; then root="$PWD/$root"; fi
    while [[ "$root" != "/" && "$root" == */ ]]; do root="${root%/}"; done
    if [[ -d "$root" ]]; then root="$(cd "$root" && pwd -P)"; fi
  elif [[ -d "$PWD/docs/simple-wiki" ]]; then
    root="$PWD/docs/simple-wiki"
  elif [[ -n "$TOPLEVEL" && "$TOPLEVEL" != "$PWD" && -d "$TOPLEVEL/docs/simple-wiki" ]]; then
    printf 'context-stats: 重定向至 git toplevel %s\n' "$TOPLEVEL" >&2
    root="$TOPLEVEL/docs/simple-wiki"
  elif [[ -n "$TOPLEVEL" && "$TOPLEVEL" != "$PWD" ]]; then
    printf 'context-stats: 重定向至 git toplevel %s\n' "$TOPLEVEL" >&2
    root="$TOPLEVEL/docs/simple-wiki"
  else
    local marker_found=0 m
    for m in AGENTS.md CLAUDE.md package.json pyproject.toml go.mod Cargo.toml mise.toml .mise.toml; do
      if [[ -e "$PWD/$m" ]]; then marker_found=1; break; fi
    done
    root="$PWD/docs/simple-wiki"
  fi
  printf '%s' "$root"
}

WIKI_ROOT_RESOLVED="$(resolve_root "${WIKI_ROOT:-}")"
WIKI_DIR="$WIKI_ROOT_RESOLVED/wiki"

PAGES=()

if [[ "${1:-}" == "--topic" ]]; then
  topic="${2:-}"
  if [[ -z "$topic" || $# -gt 2 ]]; then
    printf '用法: %s <page.md> [...] | --topic <主题名>\n' "$(basename "$0")" >&2
    exit 1
  fi
  INDEX_FILE="$WIKI_DIR/INDEX.md"
  if [[ ! -f "$INDEX_FILE" ]]; then
    printf 'context-stats: INDEX.md 不存在, --topic 不可用 (%s)\n' "$INDEX_FILE" >&2
    exit 1
  fi
  # 精确匹配 ## <主题> 段 (至下一 ##), 重名取首个并提示。
  # 不用 awk 的 == 做主题比较: macOS BSD awk (20200816) 在 UTF-8 中文下
  # 字符串等值比较返回假真值 ("求和"=="不存在" → 1), ASCII 键名不受影响。
  sep_line="$(grep -n -x "## $topic" "$INDEX_FILE" || true)"
  if [[ -z "$sep_line" ]]; then
    printf 'context-stats: 无精确匹配主题「%s」(INDEX: %s)\n' "$topic" "$INDEX_FILE" >&2
    exit 1
  fi
  if [[ "$(wc -l <<<"$sep_line")" -gt 1 ]]; then
    printf 'context-stats: 同名主题段多次出现, 取首个\n' >&2
  fi
  start="$(head -n 1 <<<"$sep_line" | cut -d: -f1)"
  end="$(awk -v s="$start" 'NR>s && /^## / { print NR; exit }' "$INDEX_FILE")"
  if [[ -n "$end" ]]; then range="${start},$((end-1))"; else range="${start},\$"; fi
  topic_files="$(sed -n "${range}p" "$INDEX_FILE" | grep -oE '\]\([^)]+\)' | sed 's/^](//; s/)$//; s/#.*$//; s/^\.\///' || true)"
  if [[ -z "$topic_files" ]]; then
    printf 'context-stats: 主题「%s」存在但段内无条目\n' "$topic" >&2
    exit 0
  fi
  while IFS= read -r t; do
    [[ -z "$t" ]] && continue
    PAGES+=("$t")
  done <<<"$topic_files"
else
  if [[ $# -lt 1 ]]; then
    printf '用法: %s <page.md> [...] | --topic <主题名>\n' "$(basename "$0")" >&2
    exit 1
  fi
  for p in "$@"; do
    if [[ "$p" == --topic ]]; then
      printf 'context-stats: --topic 不可与文件参数混用\n' >&2
      exit 1
    fi
    PAGES+=("$p")
  done
fi

# --- 全有或全无存在性检查 ----------------------------------------------------
RESOLVED=()
for p in "${PAGES[@]}"; do
  if [[ "$p" == /* ]]; then
    target="$p"
  else
    target="$WIKI_DIR/$p"
  fi
  if [[ ! -f "$target" ]]; then
    printf 'context-stats: 页不存在: %s (解析为 %s)\n' "$p" "$target" >&2
    exit 1
  fi
  RESOLVED+=("$target")
done

# --- 逐页实算, token 先求和 --------------------------------------------------
TOKEN_TOTAL=0
for f in "${RESOLVED[@]}"; do
  t="$(bash "$SCRIPT_DIR/calculation-token.sh" "$f" | sed -n 's/^tokens=//p')"
  TOKEN_TOTAL=$((TOKEN_TOTAL + t))
done

K_DISPLAY=$(( (TOKEN_TOTAL + 999) / 1000 ))
THRESHOLD_TOKEN=$(( SWARM_LIMIT * 1000 ))
ADVISE=false
if (( TOKEN_TOTAL >= THRESHOLD_TOKEN )); then ADVISE=true; fi

printf 'WIKI_ROOT=%s\n' "$WIKI_ROOT_RESOLVED"
printf 'READ_PAGES=%d\n' "${#RESOLVED[@]}"
printf 'READ_CONTEXT=%d\n' "$K_DISPLAY"
printf 'SWARM_ADVISE=%s\n' "$ADVISE"
