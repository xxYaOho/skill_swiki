# Wiki Schema

> [!TIP]
> 设计原理见 LLM_WIKI.md（仅在需要理解编译哲学时查阅, 日常维护无需读取）

## Raw material

`raw/` 中的原始材料带 frontmatter：

```yaml
---
ingested: false   # false=未编译, true=已编译
metadata: ~     # 预留扩展字段, 暂不使用
---
```

- 正文（body）永不修改，是真源；frontmatter 可编辑（元数据）。
- `ingested: false` 表示未编译：orchestrator 放入 raw/ 时标记；librarian 编译完成（wiki 页 + INDEX + LOG 都同步）后翻为 `true`。
- 增量判断新内容 = 扫描 `raw/` 中 `ingested: false` 的条目。
- `metadata` 预留，暂不使用。

## Page types

- `concept`: 想法、模式或机制（如鉴权 token 如何流转）。
- `entity`: 具体事物（服务、模块、工具、团队或个人）。
- `decision`: 做出的选择及其理由（架构决策、权衡取舍）。
- `pitfall`: 踩坑 / gotcha 及其解法（postmortem、调试记录）。
- `summary`: 阶段性汇总（阶段总结、迭代回顾）。
- `synthesis`: 复利产生的综合页（多篇 wiki 的对比、关联、汇总，独立于单次对话仍成立）。

> type 由源材料性质决定，全部经 INGEST 编译：阶段总结/迭代回顾 → `summary`；复利综合（多篇对比/关联/汇总）→ `synthesis`；其余按概念/实体/决策/坑。`summary` 是「阶段回顾」，不是「单篇源的摘要」。

## Frontmatter

每个编译页（`wiki/`）必须携带：

```yaml
---
title: <简短、具体的标题>
type: concept | entity | decision | pitfall | summary | synthesis
created: YYYY-MM-DD
updated: YYYY-MM-DD
sources: [raw/file1.md, raw/file2.md]   # 该页依据的源材料, 一律指向 raw/
topic: <所属主题, 与 INDEX 的 Topic 分组对应>
tags: [tag1, tag2]
status: current | superseded | contested
context: 16   # 该页 token 开销(单页, 不含关联文件), 单位 k, 由 scripts/calculation-token.sh 估算
---
```

`context` 是该页 token 开销的粗略估算（单页、不含关联文件），单位 k，由 `scripts/calculation-token.sh` 按字符/词数换算后向上取整。librarian 编译时运行该脚本填写。

> `raw/` 是所有源材料的统一入口, 无论来自外部文档, 还是 agent 在查阅中写下的笔记 —— 对编译而言没有区别。

## Naming

- 文件名 = title 的 kebab-case。一页一主题；当页面蔓延到不相关主题时, 拆分而非混装。

## Cross-references

- 在概念被提及处, 用相对 markdown 链接内联关联页面。只维护前向链接，不手动维护反向链接。

## Contradiction handling

- 永不静默覆盖被取代的论断；旧论断保留供溯源，不删除。
- `contested`（争议）：同一事实存在相互矛盾的论断，当前无法判定谁正确。相关论断并存，进入 ESCALATE 待人工裁决。
- `superseded`（已被取代）：旧论断已被更新的源明确取代。旧论断保留并标注新论断及来源，由 librarian 直接标记，报告中点出。

## INDEX

`wiki/INDEX.md` 按主题分组, 每页一行, 含 context 统计：

```
## <Topic>

- [title](<file>.md) | <context>k | <一句话描述> | tag, tag
```

查阅时, agent 从 INDEX 挑出候选页, 对其 `context` 求和; 总量 ≥ 64k 时派遣 swarm-reader, 否则直接阅读。

## LOG

`LOG.md` 是 wiki 操作的时间线, 倒序追加(最新在上方). 一个日期一个 `## H2`, 同日多条收纳其下:

```
## YYYY-MM-DD
- <ingest|lint> | <主题或页面> | <一句话说明>
```

## Staleness

- 一页视为过时: 当同主题下出现了更新且尚未调和的 `raw/` 源, 而该页仍停留在旧源之上。
- 过时按 LINT 的 `stale` 类型处理: 经 human 确认后记入 LINT.md 主体, 由 librarian 核实后调和(更新页面或标 `superseded`), 不得静默消除。
