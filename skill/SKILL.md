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

技能激活时按序执行:

1. 运行 `<SKILL_SCRIPTS_DIR>/doctor.sh` 读头条 (doctor 守卫已在脚本内部完成重定向并输出解析后的 `WIKI_ROOT`, 无需 orchestrator 重跑): 无 git 上下文且无标记的告警场景 → 与用户确认工作区根或设 `WIKI_ROOT`. **不直接跑 init**, 拦截误写链.
2. **只读判定 (先于任何 init)**: `WIKI_ROOT` 源于用户对外部库的显式指定 (他人项目 / 只读查阅意图) → 只读路径: 跳过 init 与一切写动作, 仅 doctor + stats + 查阅 (查阅产生的 Compound Interest 写入提议同样禁止, 产物交 orchestrator 转达库属主); 归属不明 → 向用户确认一次. 写入他人仓库是全流程最不可逆的动作.
3. `NEED_INIT=true` (自有库) → 运行 init.sh, 以 doctor 输出的 `WIKI_ROOT` 作 env 传入 (守卫发生过重定向时, 先向用户展示落点并确认) → 复跑 doctor.
4. `NEED_INIT=false` (自有库) → 仍运行一次 init.sh (幂等: 骨架静默跳过; 唯一可能动作是 AGENTS.md 缺 section 补齐, stderr 报告)——技能模板新增 H2 章节时存量工作区由此获得补齐路径; init 落点确认系于「守卫发生过重定向」事件 (step 3/4 皆然, 不系于步骤编号).
5. init 非零退出细分: 模板缺失 → 报告技能安装不完整并停止; 其他非零 (EACCES / 只读挂载 / 磁盘满) → 原样转达用户, 不误诊为安装问题.
6. 依据头条进入收录/整理/查阅分支:
   - **收录**: `RAW_PENDING>0` → 派 librarian; `RAW_INVALID_FM>0` → `--detail` 取名单, frontmatter 修复 (键缺失 / 值不合规 / 块未闭合) 作为 librarian 派单的前置步骤或 orchestrator 直接补齐, 无法机械判定时与用户确认; `RAW_PENDING_EVIDENCE>0` → 收录报告点出未接线 evidence, 不触发派遣.
   - **机械修复**: `INDEX_UNLISTED` / `INDEX_DANGLING` / `XLINK_DANGLING` / `XLINK_RAW` / `CONTEXT_DRIFT` 任一非零 → `--detail` 取名单 → 派 curator `scope: targeted` (机械修复类, 含 context 回填); 不阻塞当前查阅, 可并入同趟或下次整理.
   - **整理**: 依据 `LINT_BODY` / `LINT_ESCALATE` / `LINT_TYPES` / `LINT_PARSE` 判据 (见「馆藏整理」); `LINT_PARSE=dirty` → 先修复 LINT 结构再判整理; `PAGE_OVERSIZED>0` 并列整理信号.
   - **结构**: `INDEX_CONTEXT>32` → 向用户提议讨论收纳 (冷页归 synthesis / 主题重组), 由用户裁决.

> **定制 SCHEMA**
> (可选) SCHEMA 标准无法满足原始材料的编译时, 向用户提议是否调整 SCHEMA, 完善标准.

## Manage

两个主要的管理动作: 收录编译和馆藏整理.

### 收录编译

整理原始材料, 格式化命名和添加元信息, 放入 `simple-wiki/raw` 中. 梳理一份待清单, 派遣 librarian  (提供 `$SKILL_SCRIPTS_DIR` ) 完成最终编译.

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
- **轻微**: 派遣 curator `scope=targeted`
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
