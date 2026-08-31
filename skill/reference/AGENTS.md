# AGENTS

## Simple Wiki

只沉淀可复用知识, 一次性日志、临时命令输出、未经验证的猜测和普通 TODO 不应进入 wiki。

- 从 `docs/simple-wiki/wiki/INDEX.md` 概览项目累积的知识和事实
- `docs/simple-wiki/raw` 记录稳定原始材料：项目目标、决策、验证契约和研报等等。
- `docs/simple-wiki/wiki` 是给未来 agent 查阅的知识文档, 当某个改动产生会影响未来 agent 判断的知识时，同步更新这些页面。
- 一次性查阅资料超过 10 份时, 加载 `/yes-swiki`, 按情况安排子代理 swarm-reader
- `docs/simple-wiki/LINT.md` 记录查阅中确认的存疑文档及反馈：主体条目待 curator 核实，「ESCALATE」区块内待人工裁决. 查阅中发现存疑，先向 human 反馈，确认后才写入 LINT.md.
