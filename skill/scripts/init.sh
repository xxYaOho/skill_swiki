#!/usr/bin/env bash
# scripts/init.sh — 首次创建 docs/simple-wiki 骨架
#
# 幂等: 已存在的目录/文件一律跳过, 不覆盖, 不要求确认.
# SCHEMA.md / LLM_WIKI.md 从脚本同目录的模板拷贝为独立副本,
# 之后由馆员代理 (librarian) 在工作区维护该副本, 不再回读技能源.
# LINT.md 故意不创建: 它的存在本身即代表 wiki 有未处理问题.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WIKI_ROOT="docs/simple-wiki"

# 模板源必须在位 (脚本正确性的前提)
for tpl in SCHEMA.md LLM_WIKI.md; do
  if [[ ! -f "${SCRIPT_DIR}/${tpl}" ]]; then
    echo "错误: 缺失模板源 ${SCRIPT_DIR}/${tpl}" >&2
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
> Headline 2 为主题聚类, 无主题内容默认放在 Headline 1 中. 当同类知识找过 3 条, 需要为它们创建主题
> ---
> 一条知识内容占据一行. 先查阅编译后的知识, 按需查阅源材料.

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
> 倒序添加, 最新日志在上方. 每条以一致前缀起始, 便于查询.
> ---
> `## YYYY-MM-DD` Headline 2 为日期
> - <ingest|query|lint> | <主题或页面> | <一句话说明>

EOF
  echo "create  ${WIKI_ROOT}/LOG.md"
else
  echo "skip    ${WIKI_ROOT}/LOG.md"
fi

# SCHEMA.md — 从模板拷贝为独立副本
if [[ ! -f "${WIKI_ROOT}/SCHEMA.md" ]]; then
  cp "${SCRIPT_DIR}/SCHEMA.md" "${WIKI_ROOT}/SCHEMA.md"
  echo "create  ${WIKI_ROOT}/SCHEMA.md (from template)"
else
  echo "skip    ${WIKI_ROOT}/SCHEMA.md"
fi

# LLM_WIKI.md — 从模板拷贝为独立副本
if [[ ! -f "${WIKI_ROOT}/LLM_WIKI.md" ]]; then
  cp "${SCRIPT_DIR}/LLM_WIKI.md" "${WIKI_ROOT}/LLM_WIKI.md"
  echo "create  ${WIKI_ROOT}/LLM_WIKI.md (from template)"
else
  echo "skip    ${WIKI_ROOT}/LLM_WIKI.md"
fi
