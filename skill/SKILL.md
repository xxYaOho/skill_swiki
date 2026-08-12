---
name: yes-swiki
description: > 
  "存在于项目中的小型知识库, 两个主要使用场景: 收录和查阅. 用户提出保留文档, 笔记或研报时, 使用该技能; 任何需要了解项目信息时, 使用该技能."
argument-hint: 记录新发现, 找到 (或梳理)已有的知识
---

# Yes! Simple Wiki

管理工作时产生的研究报告, 笔记, 记录日志等等, 沉淀知识性内容便于后续查阅. 

**知识库框架**

```
docs/simple-wiki: 
- raw               # 源材料, 存入后不再修改
- wiki              # 由 Agentic 二次编译页面，每个页面对应一个概念, 实体, 主题
  - INDEX.md        # wiki 导航
- LOG.md            # 时间线日志, 持续记录 wiki 操作
- SCHEMA.md         # 规范
- LLM_WIKI.md       # 原则性指南, 源自 Karpath
```

**专属子代理**

`agents/librarian` : 管理和编译知识
`agents/swarm-reader` : 阅读者, 协作完成大量知识的阅读和消化, 提炼知识核心

## Quick Start

在工作区中执行 `ls docs | grep "wiki"`  检查是否已创建, simple-wiki 不存在时, 执行 `scripts/init.sh`  完成首次创建. 

> **定制 SCHEMA**
> (可选) SCHEMA 标准无法满足源材料的编译时, 向用户提议是否调整 SCHEMA, 完善标准.

## Workflow

从最近上下文了解当前处于哪个工作流中, 是收录(及编译), 查阅. 

### 收录

确认该知识内容的价值, 是否值得收录进 simple-wiki. 值得收录情况下, 将文档移入 `raw/` 中, 并派遣子代理 librarian 完成知识的编译.

**价值判断**

对话过程中的讨论和无法证伪结论, 不纳入知识内容范围. 探索时的研究发现, 实践时的踩坑记录和无法从代码中直接发现的知识, 才值得收录. 

### 查阅

先从 `docs/simple-wiki/wiki/INDEX.md` 了解现有内容, 再调取相关笔记文档, 做进一步查阅. 不要将  wiki 中编译后的文档作为唯一真源, 遇到前后冲突或矛盾点, 则结合 raw 源材料一起阅读, 确认真相全貌

**蜂群**

需要查阅大量资料(预计 token ≥ 64k)时, 先使用 skill yes-subagents 蜂群模式让子代理完成阅读, 从中挑出核心知识再重点查阅.

**状态**

- `DONE`: 找到且内容可信
- `UNCERTAIN`: 找到了但内容存在疑点
  - frontmatter 标为 contested/superseded，或阅读中发现与其他页/raw 材料矛盾
  - 仍可参考, 但需注明疑点，并追加一条记录到 `LOG.md` 中
- `BLOCKED`: 没有相关内容

**更新 LOG.md**

UNCERTAIN 时追加一行，延续已定的可 grep 格式：

```
## [YYYY-MM-DD] query | uncertain | <page> | <一句话疑点>
```

## Organize

发现 simple-wiki 存在矛盾点, 收到子代理的负反馈时, 评估严重程度, 安排整理工作.

**依据**

读取 `docs/simple-wiki/LINT.md`：

- 不存在或为空: 当前无未处理问题
- 有内容: 条目数量与关联性即为判断依据（标准不变：孤立少量→轻微，密集或同根因→严重）

**轻微**

孤立的 1~2 条且互不关联 (不同主题, 不同原因). 派遣 librarian 针对被标记的具体页面做局部体检和修复

**严重**

疑点数量明显偏多 (短期密集出现), 指向同一根因; librarian 自己的 ESCALATE 里有条目连续多次未被处理. 派遣 QA Combo, 带上 SCHEMA.md (作为约束标准参考), 获得报告后和用户确认修复方案, 再做进一步行动.
