#!/usr/bin/env bash
# scripts/lint.sh — 创建或追加一条记录到 docs/simple-wiki/LINT.md
#
# 用法:
#   scripts/lint.sh <source: lint|query> "<page>" "<一句话问题/疑点>"
#
# 行为:
#   - LINT.md 不存在 → 创建文件并写入表头, 再追加这条记录
#   - LINT.md 已存在 → 仅追加, 不改动已有内容(包括已被 ~~删除线~~ 包裹的行)

set -euo pipefail

usage() {
  echo "用法: $(basename "$0") <lint|query> <page> <issue>" >&2
  exit 1
}

[[ $# -eq 3 ]] || usage

SOURCE="$1"
PAGE="$2"
ISSUE="$3"

case "${SOURCE}" in
  lint|query) ;;
  *) echo "错误: source 必须是 lint 或 query，收到: ${SOURCE}" >&2; exit 1 ;;
esac

WIKI_ROOT="docs/simple-wiki"
LINT_FILE="${WIKI_ROOT}/LINT.md"
DATE="$(date +%Y-%m-%d)"

mkdir -p "${WIKI_ROOT}"

if [[ ! -f "${LINT_FILE}" ]]; then
  cat > "${LINT_FILE}" <<'EOF'
# LINT

> 文档存在时, 表示 simple-wiki 有未处理的问题. 用删除符号包裹 `~~text~~` 已解决的问题
> 所有问题被解决, 则移除本文档

EOF
fi

echo "- [${DATE}] ${SOURCE} | ${PAGE} | ${ISSUE}" >> "${LINT_FILE}"
