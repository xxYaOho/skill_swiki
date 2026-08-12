# Wiki Schema

> [!TIP]
> 设计原理见 LLM_WIKI.md（仅在需要理解编译哲学时查阅, 日常维护无需读取）

## Page types

- `concept`: 想法、模式或机制（如鉴权 token 如何流转）。
- `entity`: 具体事物（服务、模块、工具、团队或个人）。
- `decision`: 做出的选择及其理由（架构决策、权衡取舍）。
- `pitfall`: 踩坑 / gotcha 及其解法（postmortem、调试记录）。
- `summary`: 阶段性汇总（阶段总结、迭代回顾）。

## Frontmatter

每个编译页（`wiki/`）必须携带：

```yaml
---
title: <简短、具体的标题>
type: concept | entity | decision | pitfall | summary
created: YYYY-MM-DD
updated: YYYY-MM-DD
sources: [raw/file1.md, raw/file2.md]   # 该页依据的源材料, 一律指向 raw/
topic: <所属主题, 与 INDEX 的 Topic 分组对应>
tags: [tag1, tag2]
status: current | superseded | contested
context: 16   # 阅读本页预计所需上下文, 单位 k, 供 INDEX 统计与查阅预算
---
```

> `raw/` 是所有源材料的统一入口, 无论来自外部文档, 还是 agent 在查阅中写下的笔记 —— 对编译而言没有区别。

## Naming

- 文件名 = title 的 kebab-case。一页一主题；当页面蔓延到不相关主题时, 拆分而非混装。

## Cross-references

- 在概念被提及处, 用相对 markdown 链接内联关联页面。引入新概念的页面应反向链接依赖它的页面（反向链接不会自动生成, 需手动补）。

## Contradiction handling

- 永不静默覆盖被取代的论断。将旧论断标为 `status: contested` 或 `superseded`, 注明新论断及其来源, 两者并存直至人工裁决。

## INDEX

`wiki/INDEX.md` 按主题分组, 每页一行, 含 context 统计：

```
## <Topic>

- [title](<file>.md) | <context>k | <一句话描述> | tag, tag
```

## LOG

`LOG.md` 是 wiki 操作的时间线, 倒序追加(最新在上方). 一个日期一个 `## H2`, 同日多条收纳其下:

```
## YYYY-MM-DD
- <ingest|lint> | <主题或页面> | <一句话说明>
```

## Staleness

- 一页视为过时: 当同主题下出现了更新且尚未调和的 `raw/` 源, 而该页仍停留在旧源之上。记入 LINT, 不自动消除。
