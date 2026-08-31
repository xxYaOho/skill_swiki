---
name: yes-swiki
description: > 
  存在于项目中的小型知识文档图书馆, 有新的笔记文档, 研究研报等等具有知识属性的资料时, 请主动使用本技能, 进行收录
argument-hint: 收录 (或梳理) 知识
metadata:
  version: v0.5.0
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

`agents/librarian` : 收录编译知识
`agents/curator` : 馆藏整理, 核实 LINT.md 条目与全馆体检
`agents/swarm-reader` : 阅读者, 协作完成大量知识的阅读和消化, 提炼知识核心. 只读不写; 发现的存疑以 DOUBTS 交回 orchestrator.

> **DOUBTS**
> 汇总 swarm-reader 关于 DOUBTS 反馈, 先确认是否属实, 无法判断则与用户进行讨论. 最后再写入到 LINT.md 中.
> 综合蒸馏结果时做跨页对比, 发现的矛盾点也是同样.

## 准备信息

- `SKILL_SCRIPTS_DIR: <skill>/scripts`: 以 SKILL.md 所在目录为锚, `$(dirname "$(realpath <SKILL.md>)")/scripts`, 每次派遣现算, 不缓存.

## Quick Start

激活技能时, 运行 `<SKILL_SCRIPTS_DIR>/doctor.sh` 读取馆藏状态, 按 KEY 决定下一步.
外部库 (用户显式指定的他人项目) 为只读: 跳过 init 与一切写动作, 仅查阅.

- `WIKI_ROOT` / `SKILL_SCRIPTS_DIR`: 路径信息, 派遣子代理时随派单注入
- `NEED_INIT`: 是否需要初始化; 为 `true` 时运行 `<SKILL_SCRIPTS_DIR>/init.sh` (以 doctor 输出的 `WIKI_ROOT` 作 env 传入; 守卫发生过重定向时先与用户确认落点), 完成后复跑 doctor
- `RAW_PENDING`: 待编译 raw 计数; >0 → 派 librarian, 附 `--detail` 名单与 `SKILL_SCRIPTS_DIR` (编译需调用 calculation-token.sh)
- `RAW_INVALID_FM`: frontmatter 不合规的 raw (对编译不可见); >0 → `--detail` 取名单, 补齐后进入编译队列
- `RAW_PENDING_EVIDENCE`: 未被引用的 evidence; >0 → 收录报告点出, 不派遣
- `INDEX_UNLISTED` / `INDEX_DANGLING` / `XLINK_DANGLING` / `XLINK_RAW` / `CONTEXT_DRIFT`: 机械修复类; 任一 >0 → `--detail` 取名单 → 派 curator `scope: targeted` (注入两路径; context 回填调用 calculation-token.sh)
- `PAGE_OVERSIZED`: 超过 8k 的页; >0 → 并入整理信号
- `LINT_BODY` / `LINT_ESCALATE` / `LINT_TYPES`: 整理判据, 见「馆藏整理」; `LINT_PARSE=dirty` 时计数不可信, 先修复 LINT 结构
- `INDEX_CONTEXT`: 导览入口的 context 开销; 超过 32 → 提示用户, 讨论收纳

> **定制 SCHEMA**
> (可选) SCHEMA 标准无法满足原始材料的编译时, 向用户提议是否调整 SCHEMA, 完善标准.

## Manage

两个主要的管理动作: 收录编译和馆藏整理.

### 收录编译

整理原始材料, 格式化命名和添加元信息, 放入 `simple-wiki/raw` 中. 梳理一份待清单, 派遣 librarian (注入 `WIKI_ROOT` 与 `SKILL_SCRIPTS_DIR`) 完成最终编译.

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

**异常**

- 报告 context 缺算时,  orchestrator 直接运行 `<SKILL_SCRIPTS_DIR>/calculation-token.sh` 补算并回填对应页面, 不再派遣. (curator 经 doctor CONTEXT_DRIFT 名单的回填属整理趟, 优先; 两趟时序不相交.)

### 查阅

从 INDEX 挑选候选页后, 运行 `<SKILL_SCRIPTS_DIR>/context-stats.sh <候选页...>` (或 `--topic <主题名>`, Headline 1 暂挂条目走文件列表): `SWARM_ADVISE=true` → 派遣 swarm-reader; `false` → 内联直读. stats 非零退出分类处理: 缺页 → 修正清单重试; 无 topic → 核对 INDEX 主题名; 用法错 → 修命令——均不降级为无预算直读. 命中段零条目的提示注意主题名近似错字.

### 馆藏整理

两个信号来源：阅读时的即时反馈（LINT.md），以及收录后的自然演变（过时/矛盾）。判断整理时机与规模依据 doctor 头条, 不做定期体检.

- **依据**: `LINT_BODY` / `LINT_ESCALATE` / `LINT_TYPES` (`LINT_PARSE=dirty` 时先修复 LINT 结构, 计数不可信):
  - 孤立少量 → 轻微
  - 密集或同 type/根因 → 严重
  - ESCALATE 条目数偏高或持续未清 (历次激活均在) → 严重信号 (趋势由会话记忆/handoff 判断, doctor 是无状态点读取)
- **轻微**: 派遣 curator `scope=targeted` (注入 `WIKI_ROOT` 与 `SKILL_SCRIPTS_DIR`)
- **严重**: 使用 skill yes-subagents 的 quality-auditor combo, `SCHEMA.md` 作为约束参考进行全面体检, 向用户汇报结果并确认修复方案, 再由 curator 执行 `scope=full` 完成修复.

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
