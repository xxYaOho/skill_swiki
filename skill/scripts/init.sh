#!/usr/bin/env bash
# scripts/init.sh — 创建 docs/simple-wiki 骨架 + 向工作区 AGENTS.md 合并 wiki 指引
#
# 幂等: 已存在的目录/文件一律跳过, 不覆盖, 不要求确认.
# SCHEMA.md / LLM_WIKI.md 从 reference/ 拷贝为独立副本, 由馆员在工作区维护, 不再回读技能源.
# AGENTS.md(工作区根): 不存在则复制 reference/AGENTS.md; 已存在则补齐缺失的 H2 section.
# LINT.md 从 reference/ 拷贝为骨架(契约 + 「ESCALATE」区块), 之后由读者与 librarian 按契约维护.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REF_DIR="${SCRIPT_DIR}/../reference"
WIKI_ROOT="docs/simple-wiki"

# 模板源必须在位 (脚本正确性的前提)
for tpl in SCHEMA.md LLM_WIKI.md AGENTS.md LINT.md; do
  if [[ ! -f "${REF_DIR}/${tpl}" ]]; then
    echo "错误: 缺失模板源 ${REF_DIR}/${tpl}" >&2
    exit 1
  fi
done

# 目录 (幂等)
mkdir -p "${WIKI_ROOT}/raw" "${WIKI_ROOT}/wiki"

# wiki/INDEX.md — 内容导航
if [[ ! -f "${WIKI_ROOT}/wiki/INDEX.md" ]]; then
  cat > "${WIKI_ROOT}/wiki/INDEX.md" <<'EOF'
# INDEX

> [!IMPORTANT]
> Headline 2 为主题聚类, 无主题内容默认放在 Headline 1 中. 同主题条目达到 3 条时, 为它们创建独立主题.
> 每页一行, 先查阅编译后的知识, 按需查阅源材料:
> - [title](<file>.md) | <context>k | <一句话描述> | tag, tag

EOF
  echo "create  ${WIKI_ROOT}/wiki/INDEX.md"
else
  echo "skip    ${WIKI_ROOT}/wiki/INDEX.md"
fi

# LOG.md — 时间线日志
if [[ ! -f "${WIKI_ROOT}/LOG.md" ]]; then
  cat > "${WIKI_ROOT}/LOG.md" <<'EOF'
# LOG

> [!IMPORTANT]
> 倒序添加, 最新日志在上方. 一个日期一个 H2, 内部收纳多条.
> ~~~
> ## YYYY-MM-DD
> - <ingest|lint> | <主题或页面> | <一句话说明>
> ~~~

EOF
  echo "create  ${WIKI_ROOT}/LOG.md"
else
  echo "skip    ${WIKI_ROOT}/LOG.md"
fi

# SCHEMA.md — 从 reference/ 拷贝为独立副本
if [[ ! -f "${WIKI_ROOT}/SCHEMA.md" ]]; then
  cp "${REF_DIR}/SCHEMA.md" "${WIKI_ROOT}/SCHEMA.md"
  echo "create  ${WIKI_ROOT}/SCHEMA.md (from template)"
else
  echo "skip    ${WIKI_ROOT}/SCHEMA.md"
fi

# LLM_WIKI.md — 从 reference/ 拷贝为独立副本
if [[ ! -f "${WIKI_ROOT}/LLM_WIKI.md" ]]; then
  cp "${REF_DIR}/LLM_WIKI.md" "${WIKI_ROOT}/LLM_WIKI.md"
  echo "create  ${WIKI_ROOT}/LLM_WIKI.md (from template)"
else
  echo "skip    ${WIKI_ROOT}/LLM_WIKI.md"
fi

# LINT.md — 从 reference/ 拷贝为骨架
if [[ ! -f "${WIKI_ROOT}/LINT.md" ]]; then
  cp "${REF_DIR}/LINT.md" "${WIKI_ROOT}/LINT.md"
  echo "create  ${WIKI_ROOT}/LINT.md (from template)"
else
  echo "skip    ${WIKI_ROOT}/LINT.md"
fi

# AGENTS.md (工作区根) — 不存在则复制; 已存在则补齐缺失的 H2 section
# 按标题比对: 目标已有同名 H2 则跳过, 否则追加该 section (标题行到下一个 H1/H2 之前).
AGENTS_FILE="AGENTS.md"
if [[ ! -f "${AGENTS_FILE}" ]]; then
  cp "${REF_DIR}/AGENTS.md" "${AGENTS_FILE}"
  echo "create  ${AGENTS_FILE}"
else
  appended=0
  while IFS= read -r h2; do
    [[ -z "$h2" ]] && continue
    if ! grep -qF "$h2" "${AGENTS_FILE}"; then
      awk -v t="$h2" '$0==t{f=1;print;next} f&&/^##? /&&$0!=t{exit} f{print}' "${REF_DIR}/AGENTS.md" >> "${AGENTS_FILE}"
      printf '\n' >> "${AGENTS_FILE}"
      echo "append  ${AGENTS_FILE} :: ${h2}"
      appended=1
    fi
  done < <(grep -oE '^## .+' "${REF_DIR}/AGENTS.md" || true)
  [[ $appended -eq 0 ]] && echo "skip    ${AGENTS_FILE}"
fi
