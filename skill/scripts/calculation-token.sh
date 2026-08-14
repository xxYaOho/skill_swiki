#!/usr/bin/env bash
# scripts/calculation-token.sh — 粗略估算单个 wiki 页的 token 数
#
# 用法:
#   bash scripts/calculation-token.sh <file>
#
# 输出:
#   tokens=<n>     估算 token 数
#   context=<k>k   该页 context 值(向上取整到 k), 写入 frontmatter
#
# 换算规则(参考 OpenAI 主流估算, 粗略即可):
#   - 汉字: 1 字 ≈ 1 token
#   - 其它非空白字符(英文/数字/符号): 4 字符 ≈ 1 token
# 不用词数: 中文无词边界, markdown/代码也不分词, 字符数更稳.

set -euo pipefail

FILE="${1:-}"
if [[ -z "$FILE" || ! -f "$FILE" ]]; then
  echo "用法: bash $(basename "$0") <file>" >&2
  exit 1
fi

CJK=$( { grep -o '[一-龥]' "$FILE" || true; } | wc -l | tr -d ' ')
ALL=$( { grep -o '[^[:space:]]' "$FILE" || true; } | wc -l | tr -d ' ')

NON_CJK=$((ALL - CJK))
NON_CJK_TOKENS=$(( (NON_CJK + 3) / 4 ))
TOKENS=$((CJK + NON_CJK_TOKENS))
K=$(( (TOKENS + 999) / 1000 ))

echo "tokens=${TOKENS}"
echo "context=${K}k"
