---
title: Sync Token 结构化异常诊断设计
type: decision
created: 2026-08-14
updated: 2026-08-14
sources: [raw/2026-08-05-sync-token-structured-diagnostics-design.md, raw/2026-08-06-sync-token-structured-diagnostics-runtime-evidence.md]
topic: Sync Token 诊断与反馈
tags: [sync-token, diagnostics, failure-id, fatal-envelope, schema-2]
status: current
context: 2
---

# Sync Token 结构化异常诊断设计

由异常产生点提供结构化诊断：GUI 用它回答「哪里错、为什么、怎么处理」，日志用它定位 command/attempt/phase/stage/assertion/pointer/字段差异，两者消费同一事实源，不从错误字符串反推原因。依据：[Sync Token 结构化异常诊断设计](../raw/2026-08-05-sync-token-structured-diagnostics-design.md)，运行证据见 [Sync Token 结构化异常诊断运行证据](../raw/2026-08-06-sync-token-structured-diagnostics-runtime-evidence.md)。

## 设计原则

1. 事实在源头产生：parser、preflight、writer 在知道失败的位置构造 diagnostic；presenter 不解析 `Error.message`。
2. 根因与后果分离：真实 diagnostic 是 cause，`not-attempted` 是 consequence；GUI 分区，日志只展开 cause。
3. 未知就明确未知：无法确定时用 `unexpected-runtime-error`，不把推测写成建议。
4. 事务事实准确：单项 rollback 成功不等于整次零写入；同时保留 `committedWrites` 与失败项 rollback outcome。
5. 诊断不影响同步：factory/格式化失败用最小 fallback，logger 保持 best-effort。

## 诊断合同

`CauseDiagnostic` 携带稳定机器标识：`code`（失败类别）、`stage`（代码执行边界，如 `text-style.update.verify`）、`assertion`（边界内失败的不变量，如 `style-projection-equal`）、`phase`（input/preflight/runtime/rollback/command）、`operation`、`sourcePath`、`targetPointer`、`recovery`、有界 `mismatches` 与 `rollback` 状态。`stage`/`assertion` 必须能在仓库中直接 `rg` 到定义，不含动态文本。`NotAttemptedDiagnostic` 是独立的 consequence union member。

- 集中式 diagnostic factory：原生值先转普通 primitive，无法安全转换时省略 actual；unknown exception 生成 `unexpected-runtime-error` 且保留调用点的静态 phase/stage；factory 自身不向同步调用方抛错，不维护模块顶层 `RegExp`/`Set`（CocoaScript bundle 约束）。
- Failure ID：每次 attempt 最终化时为 problem 分配 `F1`、`F2` 短编号；不持久化、不跨 Retry 稳定。另生成 best-effort `eventId`（Foundation UUID，失败退化为 timestamp+command+attempt 并标记 fallback）。GUI 与日志用同一编号对应。

## 断言拆分

复合断言按现有短路顺序拆开，一次只报告第一条已证明失败的 assertion，不为收集更多错误增加原生 getter 调用。runtime assertion 包括：`input-field-applied`、`returned-ownership-local`、`stable-id-present`、`stable-id-unique`、`collection-position-stable`、`asset-name-equal`、`style-type-equal`、`style-projection-equal`（记录 owned fields 最小 diff）、`swatch-binding-equal`、`binding-ids-stable`、`binding-style-equal`。

无法从 projection 证明「字体未安装」时只显示「Sketch 未保留指定字体」，`check-font` 不得被表述为已证明缺少字体。

## Fatal envelope

fatal 场景不返回普通 `SyncResult`，使用 plain branded envelope（`__syncTokenFatal: 1`，不依赖跨 bundle 不可靠的 `instanceof`）：

- `policy-fatal`：create 返回 foreign/unknown ownership，cleanup 已成功但 hard policy 要求停止；`currentItem.state: restored`，不伪造 rollback failure。
- `recovery-fatal`：cleanup/restore 或其 verification 失败；`phase: rollback` 为首因，原 runtime cause 保留为 `cause`，`currentItem.state` 为 `unknown` 或 `partially-mutated`。

两类都携带进入当前失败项之前的 confirmed progress；命令层均阻止 Retry，并不得声称此前成功写入已回滚。

## GUI：原因优先

失败 modal 首屏：`Problems` 固定首位自动展开（只含真实 diagnostics，problem card 含原因、资产名、有界 expected/actual、一条建议、可复制 `F#`）；`Not Synced` 只含 `not-attempted` 默认折叠；Added/Updated/Unchanged 保留独立计数。摘要语义受严格约束：不得使用「同步已全部回滚」这类无法由结果字段证明的文案；只有 `DiagnosticLogReceipt` 证明日志已写入时才提示「在日志中查找 eventId/F#」，否则明确说明技术详情未写入日志。成功结果沿用现有[结果 Modal](sync-token-result-modal.md) 行为。

## 日志 schema 2

外层保留 schema 1 字段语义（见[独立 NDJSON 日志设计](sync-token-ndjson-logging.md)）并升级 `schema: 2`：增加 `eventId`、runtime 版本（pluginVersion 读自安装 manifest，不新增硬编码真源）、结构化 `failures`（failureId、collectionKind、sourcePointer、diagnostics 数组含 phase/stage/assertion/mismatches/rollback）。

大小与隐私：单事件 256 KiB、双文件 5 MiB、锁合同不变；pointer 超 8 KiB 改写为 `{ prefix, suffix, utf8Bytes, fnv1a32, truncated: true }`；每 problem 最多 8 条 diagnostics、每条最多 8 项 mismatch；截断优先级固定，首因 problem 不整体丢弃；绝对路径脱敏，相对 token name 不得被吞掉。logger 返回不抛异常的 `DiagnosticLogReceipt`，receipt 只影响 GUI 交叉引用提示，不参与 completion、Retry 或 `lastSynced`。

## 运行证据（2026-08-06）

- 单插件 23 文件 391 测试、typecheck、build 通过；dist/installed manifest 与 5 个 command SHA-256 一致；重启 Sketch 后以 schema 2 特有行为证明进程已加载新 bundle。
- 正式路径：invalid reference 事件（`missing-color-target` / `input.resolve.reference` / `target-exists`）GUI 首屏首因可见，`eventId/F1` 与日志逐字对应；Retry 产生独立 attempt/event；Add Slot 文件选择器能进入结果 modal 而非通用 alert。
- fatal 与日志降级（policy/recovery fatal、unknown exception、receipt full/partial/dropped）由任务专属 harness 在真实 CocoaScript/AppKit 中验证，不冒充原生 failure 的生产复现。
- 已接受的证据缺口（Human 授权）：共享文档缺验收前完整 projection/binding 快照；fatal harness 截图与 ID 未落盘。验收期间误选 `orca2sketch.json` 产生的 80 个新增资产已按稳定 ID 增量精确删除，数量恢复且无绑定残留。
