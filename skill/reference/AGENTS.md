# AGENTS
## Simple Wiki

只沉淀可复用知识, 一次性日志、临时命令输出、未经验证的猜测和普通 TODO 不应进入 wiki。

- `docs/simple-wiki/raw` 记录稳定原始材料：项目目标、决策、验证契约和研报等等。
- `docs/simple-wiki/wiki` 是给未来 agent 查阅的知识文档, `INDEX.md` 是目录导览, 优先从导览开始查阅。当某个改动产生会影响未来 agent 判断的知识时，同步更新这些页面。
- 大量查阅资料时, 使用 skill yes-swiki 专属子代理 swarm-reader 完成阅读; 候选页 context 总和阈值见 SCHEMA.md。
- `docs/simple-wiki/LINT.md` 记录查阅中确认的存疑文档及反馈：主体条目待 curator 核实，「ESCALATE」区块内待人工裁决. 查阅中发现存疑，先向 human 反馈，确认后才写入 LINT.md.
