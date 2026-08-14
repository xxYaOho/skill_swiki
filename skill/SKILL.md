---
name: yes-swiki
description: > 
  存在于项目中的小型知识文档图书馆, 有新的笔记文档, 研究研报等等具有知识属性的资料时, 请主动使用本技能, 进行收录
argument-hint: 收录 (或梳理) 知识
matedata:
  version: v0.1.0
---

# Yes! Simple Wiki

管理工作时产生的研究报告, 笔记, 记录日志等等, 沉淀知识性内容便于后续查阅. 

**知识库框架**

```
docs/simple-wiki: 
- raw               # 原始材料, 存入后不再修改
- wiki              # 由 Agentic 二次编译页面，每个页面对应一个概念, 实体, 主题
  - INDEX.md        # wiki 导航
- LOG.md            # 时间线日志, 持续记录 wiki 操作
- SCHEMA.md         # 规范
- LLM_WIKI.md       # 原则性指南, 源自 Karpath
- LINT.md           # 健康记录
```

**专属子代理**

`agents/librarian` : 管理和编译知识
`agents/swarm-reader` : 阅读者, 协作完成大量知识的阅读和消化, 提炼知识核心. 只读不写; 发现的存疑以 DOUBTS 交回 orchestrator.

> **DOUBTS**
> 汇总 swarm-reader 关于 DOUBTS 反馈, 先确认是否属实, 无法判断则与用户进行讨论. 最后再写入到 LINT.md 中.
> 综合蒸馏结果时做跨页对比, 发现的矛盾点也是同样.

## Quick Start

在工作区中执行 `ls docs/simple-wiki` 检查是否已创建, 不存在时执行 `scripts/init.sh` 完成首次创建.

> **定制 SCHEMA**
> (可选) SCHEMA 标准无法满足原始材料的编译时, 向用户提议是否调整 SCHEMA, 完善标准.

## Manage

两个主要的管理动作: 收录编译和馆藏整理.

### 收录编译

整理原始材料, 格式化命名和添加元信息, 放入 `simple-wiki/raw` 中. 梳理一份待清单, 派遣 librarian 完成最终编译.

```yml
---
class: material   # material=正常编译; evidence=仅作引用凭证
ingested: false   # true=已处理 (已编译, 或已被引用)
metadata: ~       # 收纳源文档自带 frontmatter 的原有字段, 无则 ~
---
```

**收录判据**

收录:
- 可复用、已验证的知识: 研究发现, 踩坑记录, 无法从代码直接发现的隐性知识
- 需求与背景: plan 类文档承载需求本身与决策背景
- 被馆藏引用的文档: 即使本身未执行 (如验证计划), 被引用即收录, 保持溯源链完整
- 验收凭证 (evidence): 构建产物哈希 / 运行时日志 / 测试基线等时点性验证记录, 标记 `class: evidence` 入 raw 供溯源, 不单独编译成页, 由相关编译页在 sources 中引用

源文档自带 frontmatter 时, 原有字段收纳进 `metadata` 保留, 不丢弃 (正文以原 frontmatter 块之后为准).

不收录: 纯施工清单 (checkbox TODO), 一次性状态日志, 临时输出, 未经验证的猜测。

### 馆藏整理

两个信号来源：阅读时的即时反馈（LINT.md），以及收录后的自然演变（过时/矛盾）。判断整理时机与规模依据 LINT.md 现状，不做定期体检。

- **依据**: 读取 LINT.md「ESCALATE」区块之前的条目, 为空则跳过整理; 有条目时, 数量与关联性即为判据:
  - 孤立少量 → 轻微
  - 密集或同 type/根因 → 严重
  - ESCALATE 区块若持续增长，同样视为严重信号。
- **轻微**: 派遣 librarian `mode=LINT scope=targeted`
- **严重**: 使用 skill yes-subagents 的 quality-auditor combo, `SCHEMA.md` 作为约束参考进行全面体检, 向用户汇报结果并确认修复方案, 再由 librarian 执行 `mode=LINT scope=full` 完成修复.

## Compound Interest

查阅本身也产生知识. 发现值得沉淀的综合内容（多篇 wiki 的对比、关联、汇总, 且独立于本次对话仍成立）时, 主动向用户提议 (或响应要求). 获得用户确认后, 整理相关知识, 撰写笔记存入 `raw/`, 派遣 librarian 随后跟进编译. 独立篇与综合篇并存, 冗余可接受.

知识复利笔记注明综合自哪些 wiki, 尽量保证溯源链不断. 何时压缩精炼由用户把握.

```
综合页 → raw 笔记 → 原 wiki 页 → 各自 raw
```

**复利循环**

```
行动 / 目标
  ↓
查阅 Simple Wiki → 事实 (知识) 来源
  ↓
推进实现 / 目标达成
  ↓
收尾, 可复用知识回写 raw/ 与 wiki/
  ↺
```
