# librarian/curator 拆分迭代发现（2026-08-31）

针对子代理拆分后的模型选型与契约做了三轮 staged eval（iteration-4 编译 A/B、iteration-5 seeded-LINT A/B、真库全馆扫描 supplement）。本文记录应超出单次 eval 生命周期的发现。详细数据见 `yes-swiki-workspace/iteration-5/eval-curator{,-full}/SUMMARY.md`。

## 结论：双 haiku + 契约封顶原则

librarian@haiku（`0befe3e`）与 curator@haiku（用户确认）。依据：四分岔契约把不可裁决项上抛 ESCALATE，curator 所需能力被契约封顶，判定轴双臂满分、时长持平（657s vs 680s）。

此结论有前提：**契约不变**。若放宽 ESCALATE 门槛、扩大 curator 自主裁决面，"haiku 足够" 不自动延续。

## 最耐久的产出是契约修正

eval 抓到 curator.md 两处自相矛盾并已修（`6ff7cf8`）：

- outcome-2（误报）原无反证要求，删行无据可查 → 现要求报告注明反证及出处。
- LOG 记录规则（L33 "每 run 记一条"）与分条目规则冲突 → 现明确 outcome 1/4 记、2 不记。

启示：eval 检验的不只是模型，还有契约本身；契约措辞歧义会被子代理以不同合理方式解读。

## curator@haiku 的两个风险特征（各 1 样本，复现再议）

1. **正确方向 + 臆造具体性**：对齐 `help --llm` → `--help-llm`（方向正确、cli 页可证）时，附加了 raw 零出处的 "0.25.5 起全树 flag，旧形态已退役"。同场景 sonnet 的对齐全部带 raw 引用。
2. **ESCALATE 区块越位**：契约要求 full-scope 新发现追加在区块之前，haiku 将新发现直接移入区块（targeted outcome-3 的流程）。

## scope:full 的体检价值

真库全馆扫描从存量 KB 捞出 2 处非播种的真实缺陷（双臂均报）：

- `raw/260827-peony-025-m4-drill-record.md` 完全缺 frontmatter，ingest 增量扫描不可见（内容已被 wiki 引用）。
- `peony-nas-deploy-pitfalls.md` 的 2026-08-30 宕机事件节无对应 raw 溯源。

属 peony 上游数据问题，待回写。另：`tests/docs-peony` 的 LINT.md 契约头仍是拆分前旧措辞（"由 librarian 核实处理"），应随 skill/reference/LINT.md 现行措辞刷新。

## 方法论沉淀

- **一轮冷启动 eval 测不了 curator**：iteration-4 的一次性 init 场景不产生 LINT 条目，8 个沙箱 LINT 全空——结构性缺陷，非模型差异。
- **可复用的 fixture 模式**：真库复制 + 播种未列锚点（测召回）+ 列出条目（测精度，含语义误报与已裁决 ESCALATE 不误删）+ 随机噪声（附加分）；评分器双自校准（机械 perfect 解须满分、noop 须只余空转 pass），先校准再评臂。
- 陷阱设计有效案例："更新的源明确取代才算 superseded"（SCHEMA.md），播种了 date-newer-wins 诱导，双臂均未上当。

## 未闭合

- 方案 B（多轮 ingest，测 librarian→curator 接缝信息保真）未做——模型分配证据中唯一悬空的柱子。
- haiku 风险特征与"契约封顶"的边界均基于小样本，不宜表述为"已证伪 sonnet"。
