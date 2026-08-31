#!/usr/bin/env bash
# scripts/init.sh — 创建 docs/simple-wiki 骨架 + 向工作区 AGENTS.md 合并 wiki 指引
#
# 幂等: 已存在的目录/文件一律跳过, 不覆盖, 不要求确认.
# 静默: 骨架件检查与创建不输出 stdout (检查职责归 doctor.sh);
#       AGENTS.md 的 create 与 H2 追加向 stderr 报告 (含完整路径, 落点可观测).
# 路径: WIKI_ROOT env 覆盖优先, 缺省走守卫阶梯 (CWD 有库 → 尊重 CWD;
#       git toplevel 有库 → 重定向). AGENTS.md 落点: WORKSPACE_ROOT env >
#       WIKI_ROOT 剥尾部 /docs/simple-wiki > CWD. 不用 dirname (只上溯一层,
#       标准布局会落到 docs/ 里).
# SCHEMA.md / LLM_WIKI.md 从 reference/ 拷贝为独立副本, 由馆员在工作区维护, 不再回读技能源.
# AGENTS.md(工作区根): 不存在则复制 reference/AGENTS.md; 已存在则补齐缺失的 H2 section.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REF_DIR="${SCRIPT_DIR}/../reference"

# --- 根解析: 守卫阶梯 (与 doctor.sh 同语义, §4 为单一规范源) ----------------
TOPLEVEL="$(git rev-parse --show-toplevel 2>/dev/null || true)"

resolve_wiki_root() {
  local root=""
  if [[ -n "${WIKI_ROOT:-}" ]]; then
    root="$WIKI_ROOT"
    if [[ "$root" != /* ]]; then root="$PWD/$root"; fi
    while [[ "$root" != "/" && "$root" == */ ]]; do root="${root%/}"; done
    if [[ -d "$root" ]]; then root="$(cd "$root" && pwd -P)"; fi
  elif [[ -d "$PWD/docs/simple-wiki" ]]; then
    root="$PWD/docs/simple-wiki"
  elif [[ -n "$TOPLEVEL" && "$TOPLEVEL" != "$PWD" && -d "$TOPLEVEL/docs/simple-wiki" ]]; then
    printf 'init: 重定向至 git toplevel %s\n' "$TOPLEVEL" >&2
    root="$TOPLEVEL/docs/simple-wiki"
  elif [[ -n "$TOPLEVEL" && "$TOPLEVEL" != "$PWD" ]]; then
    printf 'init: 重定向至 git toplevel %s\n' "$TOPLEVEL" >&2
    root="$TOPLEVEL/docs/simple-wiki"
  else
    root="$PWD/docs/simple-wiki"
  fi
  printf '%s' "$root"
}

WIKI_ROOT_RESOLVED="$(resolve_wiki_root)"

# --- AGENTS.md 落点: WORKSPACE_ROOT env > 剥后缀 > CWD ----------------------
resolve_workspace_root() {
  if [[ -n "${WORKSPACE_ROOT:-}" ]]; then
    local ws="$WORKSPACE_ROOT"
    if [[ "$ws" != /* ]]; then ws="$PWD/$ws"; fi
    printf '%s' "$ws"
    return
  fi
  local suffix="/docs/simple-wiki"
  if [[ "$WIKI_ROOT_RESOLVED" == *"$suffix" ]]; then
    local ws="${WIKI_ROOT_RESOLVED%"$suffix"}"
    if [[ -n "$ws" ]]; then
      printf '%s' "$ws"
      return
    fi
  fi
  printf '%s' "$PWD"
}

WORKSPACE_ROOT_RESOLVED="$(resolve_workspace_root)"

# 模板源必须在位 (脚本正确性的前提)
for tpl in SCHEMA.md LLM_WIKI.md AGENTS.md LINT.md; do
  if [[ ! -f "${REF_DIR}/${tpl}" ]]; then
    echo "错误: 缺失模板源 ${REF_DIR}/${tpl}" >&2
    exit 1
  fi
done

# --- 骨架 (幂等, 静默) --------------------------------------------------------
mkdir -p "${WIKI_ROOT_RESOLVED}/raw" "${WIKI_ROOT_RESOLVED}/wiki"

# wiki/INDEX.md — 内容导航
if [[ ! -f "${WIKI_ROOT_RESOLVED}/wiki/INDEX.md" ]]; then
  cat > "${WIKI_ROOT_RESOLVED}/wiki/INDEX.md" <<'EOF'
# INDEX

> [!IMPORTANT]
> Headline 2 为主题聚类, 无主题内容默认放在 Headline 1 中. 同主题条目达到 3 条时, 为它们创建独立主题.
> 每页一行, 先查阅编译后的知识, 按需查阅源材料:
> `- [title](<file>.md) | <context>k | <一句话描述> | tag, tag`

EOF
fi

# LOG.md — 时间线日志
if [[ ! -f "${WIKI_ROOT_RESOLVED}/LOG.md" ]]; then
  cat > "${WIKI_ROOT_RESOLVED}/LOG.md" <<'EOF'
# LOG

> [!IMPORTANT]
> 倒序添加, 最新日志在上方. Headline 2 为日期, 内部收纳多条日志.
> ~~~
> ## YYYY-MM-DD
> - <ingest|lint> | <主题或页面> | <一句话说明>
> ~~~

EOF
fi

# SCHEMA.md / LLM_WIKI.md / LINT.md — 从 reference/ 拷贝为独立副本
for tpl in SCHEMA.md LLM_WIKI.md LINT.md; do
  if [[ ! -f "${WIKI_ROOT_RESOLVED}/${tpl}" ]]; then
    cp "${REF_DIR}/${tpl}" "${WIKI_ROOT_RESOLVED}/${tpl}"
  fi
done

# --- AGENTS.md (工作区根) — 全分支可观测 -------------------------------------
# 按标题整行比对 (strip 尾随空白): 目标已有同名 H2 则跳过, 否则追加该 section
# (标题行到下一个 H1/H2 之前). 首次创建与每次追加均向 stderr 报告落点.
AGENTS_FILE="${WORKSPACE_ROOT_RESOLVED}/AGENTS.md"
if [[ ! -f "${AGENTS_FILE}" ]]; then
  cp "${REF_DIR}/AGENTS.md" "${AGENTS_FILE}"
  printf 'create %s (from template)\n' "${AGENTS_FILE}" >&2
else
  appended=0
  while IFS= read -r h2; do
    [[ -z "$h2" ]] && continue
    h2_trimmed="$(printf '%s' "$h2" | sed 's/[[:space:]]*$//')"
    if ! awk -v t="$h2_trimmed" '{ cur=$0; sub(/[[:space:]]+$/, "", cur); if (cur == t) found=1 } END { exit found ? 0 : 1 }' "${AGENTS_FILE}"; then
      awk -v t="$h2_trimmed" '$0==t{f=1;print;next} f&&/^##? /&&$0!=t{exit} f{print}' "${REF_DIR}/AGENTS.md" >> "${AGENTS_FILE}"
      printf '\n' >> "${AGENTS_FILE}"
      printf 'append %s :: %s\n' "${AGENTS_FILE}" "${h2_trimmed}" >&2
      appended=1
    fi
  done < <(grep -oE '^## .+' "${REF_DIR}/AGENTS.md" || true)
  # 已存在且无追加: 静默
  true
fi
