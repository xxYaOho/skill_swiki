---
title: Sync Token 结构化异常诊断设计
type: decision
created: 2026-08-24
updated: 2026-08-24
sources: [raw/2026-08-05-sync-token-structured-diagnostics-design.md, raw/2026-08-06-sync-token-structured-diagnostics-runtime-evidence.md]
topic: Sync Token 诊断与反馈
tags: [sync-token, diagnostics, failure-id, rollback, ndjson, appkit, verification]
status: current
context: 4
---

# Sync Token 结构化异常诊断设计

Sync Token 将失败事实从异常产生点传递到结果 Modal 与 NDJSON 日志，避免展示层从 `Error.message` 反推根因。设计不改变 parser 接受范围、preflight 零写入门禁、资产写入顺序、fail-fast、单项 rollback、Retry 或 `lastSynced` 条件。依据：[Sync Token 结构化异常诊断设计](../raw/2026-08-05-sync-token-structured-diagnostics-design.md)。运行时结果与限制见 [Sync Token 结构化异常诊断运行证据](../raw/2026-08-06-sync-token-structured-diagnostics-runtime-evidence.md)。

## 核心原则

- 诊断在 parser、preflight、writer、rollback 和 command boundary 的事实产生点构造，presenter 不解析错误字符串。
- 根因与后果分离：真实 failure 是 cause；后续未执行项统一是 `not-attempted` consequence。
- GUI 展示用户可理解的原因、差异和处理建议；日志保留稳定定位字段和受限技术细节。
- 无法确定原因时使用 `unexpected-runtime-error` 或 `unexpected-command-error`，不伪造 assertion、mismatch 或 recovery。
- 诊断构造、格式化和日志写入失败不得改变同步结果；factory 自身不得向同步调用方抛错。
- 事务事实必须准确区分 `committedWrites` 与失败项 rollback outcome，不能把部分恢复描述成整次同步零写入。

## 诊断合同

诊断分为两类：

```ts
type SyncDiagnostic = CauseDiagnostic | NotAttemptedDiagnostic

interface CauseDiagnostic {
  kind: 'cause'
  code: string
  phase: 'input' | 'preflight' | 'runtime' | 'rollback' | 'command'
  operation: 'parse' | 'index' | 'create' | 'update' | 'verify' |
    'cleanup' | 'restore' | 'read' | 'write' | 'present'
  stage: string
  assertion?: string
  sourcePath: string[]
  targetPointer?: string
  recovery: RecoveryKind
  mismatches?: DiagnosticMismatch[]
  rollback?: RollbackDiagnosticState
  message: string
}

interface NotAttemptedDiagnostic {
  kind: 'consequence'
  code: 'not-attempted'
  phase: 'preflight' | 'runtime'
  operation: 'skip'
  stage: 'sync.not-attempted'
  sourcePath: string[]
  message: string
}
```

`code` 表示失败类别，`stage` 表示执行边界，`assertion` 表示该边界内失败的具体不变量。三者以及 `recovery` 必须由导出的 typed constants 定义，producer、presenter 和测试共享同一组常量。`message` 只用于兼容和 fallback，Modal 与 logger 不得根据它推导结构化事实。

Factory 负责校验 plain object、primitive 和短数组边界，把 Cocoa 原生值转为普通 primitive，并对 unknown exception 生成保留静态 `phase`、`operation`、`stage` 的 fallback。不能安全读取原错误或 native getter 时，使用固定的 `Unexpected error.`，省略无法证明的 `actual`。Factory 不在模块顶层维护 `RegExp`、`Set` 或原生对象，以符合 CocoaScript bundle 运行时约束。

## Failure ID 与事件关联

一次 sync attempt 最终化结果时，将同一 `SyncItemResult` 中除 `not-attempted` 外的 diagnostics 聚合为一个 problem，并按展示顺序分配事件内短编号 `F1`、`F2`。编号不跨 Retry 稳定，也不参与资产身份、去重或事务判断。`not-attempted` 不分配 failure ID。

每个 attempt 或 command error 另生成 best-effort `eventId`。优先使用 Foundation UUID 并立即转为普通字符串；UUID bridge 失败时退化为 timestamp、command 和 attempt 组成的 correlation value，并标记 `eventIdSource: fallback`。`eventId` 只用于 GUI 与日志对照，不作为唯一身份。只有日志 receipt 证明写入成功后，GUI 才显示可查找的 `eventId/F#`。

## 错误分类与排序

输入和 preflight 诊断必须只报告 parser 或 eligibility gate 已证明的事实，不能根据 asset name 猜测 token 类型。典型输入错误包括：

- `invalid-color-reference`：引用不是完整 `@/` RFC 6901 pointer。
- `missing-color-target`：目标 pointer 不存在。
- `non-color-target`：目标存在但不是 color token。
- `invalid-token-field`：字段名或字段约束不满足。
- `unknown-token-node`：出现未知节点类别。
- `ambiguous-token-file`：根格式不唯一。

典型 preflight 错误包括 `duplicate-document-target`、`asset-ownership-unavailable` 和 `migration-unsupported`。Library asset 继续排除，不作为 duplicate、update 或 rollback target。与 [Sync Token 本地资产所有权设计](sync-token-local-asset-ownership.md) 和 [Sketch 资产运行时特性](sketch-asset-runtime-characteristics.md) 的所有权、stable ID 与 snapshot 约束保持一致。

runtime writer 将 create/update 的复合验证按既有短路顺序拆成单一 assertion，包括：

- `input-field-applied`
- `returned-ownership-local`
- `stable-id-present`
- `stable-id-unique`
- `collection-position-stable`
- `asset-name-equal`
- `style-type-equal`
- `style-projection-equal`
- `swatch-binding-equal`
- `binding-ids-stable`
- `binding-style-equal`

一次只报告第一条已证明失败的 assertion，不为收集更多错误而增加原生 getter 或越过短路点。setter 直接抛错使用 `input-field-applied`；静默写入不一致只能由已有 plain projection 产生 `style-projection-equal`。projection mismatch 只保留有限字段差异：Text Style 比较字体、字号、字重、行高、字距和 Text Swatch identity；Swatch 比较名称、canonical color、stable ID 与 collection position；Layer Style 只记录 canonical projection 的首个差异和有界 primitive 或 count/hash 摘要。

字体无法从 projection 证明未安装时，GUI 只能说 Sketch 未保留指定字体，并建议检查字体名称与本机可用性，不得把名称错误、字重不匹配或 Sketch fallback 断言为字体缺失。

## Rollback 与 fatal envelope

普通可恢复 runtime failure 在主 diagnostic 上附带 rollback 状态：

```json
{
  "rollback": {
    "attempted": true,
    "outcome": "succeeded",
    "stage": "text-style.update.restore"
  }
}
```

update verification 的恢复失败或无法确认、create cleanup 失败、出现 unknown delta、collection identity 无法恢复、资产 ownership 变为 foreign/unknown，均不能返回普通完成态。实现使用 plain branded `SyncFatalEnvelope`，由命令层通过 property guard 识别，不依赖跨 CocoaScript bundle 不可靠的 `instanceof`。

- `policy-fatal`：cleanup 成功且 collection identity 已恢复，但 create 返回的资产 ownership 不可信；主 diagnostic 保留真实 runtime/create/`returned-ownership-local`，当前项为 `restored`，recovery 为 `inspect-log`，禁止 Retry。
- `recovery-fatal`：cleanup、restore 或 verification 失败；rollback diagnostic 成为 fatal 主因，原 runtime diagnostic 作为 `cause`，当前项为 `unknown` 或 `partially-mutated`，recovery 为 `stop-and-recover-document`，禁止 Retry。

两类 envelope 都携带进入当前失败项之前的 confirmed progress。`committedWrites` 只代表此前已经确认的 added/updated 数量，不代表当前失败资产的最终状态，也不代表文档总变更数。rollback outcome 是原始 cause 的附属恢复状态；只有 recovery 自身失败升级为 `recovery-fatal` 时，rollback 才成为 fatal 主因。

## GUI 结果模型

失败 Modal 采用 cause-first 结构：

```text
Sync stopped
1 problem stopped 10 later items. 73 earlier changes completed.

Problems                                              1
  [text] mono-body                         F1
         v2/display
         Sketch did not retain the requested font.
         Expected: Departure Mono
         Actual: PingFang SC
         Check the font name and local availability, then retry.

Not Synced                                           10
Added                                                57
Updated                                              16
Unchanged                                             5
```

规则如下：

- `Problems` 固定首位并自动展开，只包含真实 diagnostics。
- `Not Synced` 只包含 `not-attempted`，默认折叠；标题说明这些项因上述问题未执行。
- Added、Updated、Unchanged 保留独立计数和逐项明细，默认折叠。
- 同一资产的多条真实 diagnostics 合并为一张 problem card，只分配一个 failure ID。
- 普通 runtime 首因排在其他 runtime diagnostics 前；preflight 按 canonical source path 与 code 稳定排序。
- 每张 card 最多显示用户可理解的原因、资产路径、有限 expected/actual、一条处理建议和 `F#`。
- GUI 不显示内部 stage、assertion、selector、Cocoa wrapper、完整 Error 或 stack。
- unknown diagnostic 只显示未知异常文案；仅当 receipt 证明日志已写入对应 failure 时，才追加 `eventId/F#` 查找提示。
- `committedWrites > 0` 时只能说明此前已完成的修改；不能显示“全部回滚”或“没有修改”。
- fatal rollback 显示当前资产状态未知或部分变更，并取消 Retry。

保持原生 `NSPanel`、固定宽度、纵向滚动、adaptive colors、可选择文本以及 Return/Escape、Retry 和 panel cleanup 合同。`Not Synced` 只在 Modal model 聚合，不从 `SyncResult.items` 删除条目。Retry 重新读盘并创建新的 attempt，不复用旧 diagnostic。

## NDJSON schema 2

日志保留 schema 1 的外层语义并升级为 schema 2，增加 `eventId`、`eventIdSource`、runtime metadata、结构化 failures、`committedWrites` 与有限 rollback 信息：

```json
{
  "schema": 2,
  "event": "sync-result",
  "eventId": "6E5AF241-575B-41C3-9E15-B87F41640291",
  "eventIdSource": "uuid",
  "command": "sync-current",
  "attempt": 1,
  "source": "orca2sketch.json",
  "runtime": {
    "pluginVersion": "1.2.1",
    "sketchVersion": "2026.3",
    "apiVersion": "2.0.0"
  },
  "complete": false,
  "counts": {
    "added": 57,
    "updated": 16,
    "unchanged": 5,
    "skipped": 11
  },
  "committedWrites": 73,
  "notAttempted": 10,
  "failures": [
    {
      "failureId": "F1",
      "collectionKind": "text-style",
      "name": "v2/display/mono-body",
      "sourcePointer": "/v2/display/mono-body",
      "diagnostics": [
        {
          "code": "field-mismatch",
          "phase": "runtime",
          "operation": "verify",
          "stage": "text-style.update.verify",
          "assertion": "style-projection-equal",
          "recovery": "check-font",
          "mismatches": [
            {
              "field": "fontFamily",
              "expected": "Departure Mono",
              "actual": "PingFang SC"
            }
          ],
          "rollback": {
            "attempted": true,
            "outcome": "succeeded",
            "stage": "text-style.update.restore"
          }
        }
      ]
    }
  ]
}
```

日志保持原有容量、锁和脱敏边界：

- 单事件最多 256 KiB，当前日志与单一备份各最多 5 MiB。
- source 只记录 basename；不记录 document path、完整 token、原生 Cocoa 对象或 stack trace。
- pointer 在 8 KiB UTF-8 内完整保留；超限改为 prefix/suffix/UTF-8 byte count/FNV-1a fingerprint 的 bounded locator。
- 每个 problem 最多 8 条 diagnostics，每条 mismatch 最多 8 项，并记录 omission 元数据。
- 截断优先保留固定字段、首因结构、fatal rollback，再处理其他 failure、mismatch 和 message。
- `not-attempted` 只记录总数，不进入 failures。
- logger 失败、锁竞争、stale lock、文件类型异常或磁盘失败都只丢弃本次记录，不改变同步结果。

日志写入返回不抛异常的 `DiagnosticLogReceipt`，包含 `written`、`eventId`、完整包含、部分包含和省略的 failure ID。Modal 只引用 receipt 已证明写入的 failure；部分技术详情显示降级提示，日志丢弃或 failure 整体省略时明确说明技术详情未写入日志。

command error 保留稳定步骤标签，例如 `source.pick`、`source.read`、`source.parse-json`、`slot.save`、`sync.run`、`last-synced.update` 和 `result.present`，并使用 `source-read-failed`、`json-parse-failed`、`slot-save-failed`、`result-presentation-failed` 或 `unexpected-command-error` 等稳定 code。runtime metadata 在 command boundary 只读取一次；读取失败时省略该字段，不影响同步。

## 实施与验收边界

推荐依赖顺序：

1. 扩展 diagnostic 类型、factory 和 schema 2 formatter。
2. 迁移 parser、`canAttemptSync()` eligibility gate 与 preflight，确保可识别 input diagnostic 进入结果 Modal。
3. 按 Swatch、Layer Style、Text Style 拆分 create/update assertion。
4. 结构化 rollback、cleanup 和 command fatal envelope。
5. 切换 Modal 为 Problems / Not Synced，并切换 logger schema 2。
6. 通过自动化、临时 diagnostic harness、正式安装 bundle 和隔离 Sketch 文档验收。

自动化必须覆盖稳定 code/phase/operation/stage/recovery、unknown fallback、native getter failure、failure ordering、field-level mismatch、fatal progress、bounded logging、路径脱敏和多字节截断。真实 Sketch command 只承担能稳定触发的产品路径；ownership、native setter 和 fatal restore 使用 Node fault-injection tests 与任务专属 CocoaScript/AppKit harness 验证。harness 证明诊断传播和展示合同，不等同于正式产品路径稳定复现原生异常。

## 运行证据与限制

2026-08-06 的运行证据确认：

- Sync Token 单插件 test 通过 23 个测试文件、391 个测试，typecheck 与 build 通过。
- dist manifest、installed manifest 与 5 个正式 command 的 SHA-256 一致，正式 bundle 不含临时 fatal harness 标识。
- 重启 Sketch Beta 后，正式 `Sync Current` 能在真实 Modal 与 schema 2 日志中展示 `missing-color-target`、`input.resolve.reference`、`target-exists`、`fix-source`，Problems 首位显示首因，Not Synced 默认折叠。
- Retry 使用新 event ID 和 `attempt: 2`；complete no-op 只显示 `Unchanged 1`，且只有 complete 结果更新 `lastSynced`。
- Add Slot 对可识别 input diagnostic 进入正式结果 Modal，而完全无关 JSON 仍由自动测试覆盖拒绝。
- fatal、unknown exception、receipt full/partial/dropped 行为在 disposable 文档和独立 harness/log root 中验证，临时文档、fixture、bundle 与日志目录随后删除。

证据仍有明确限制：fatal harness 的截图、event/failure ID 和临时日志摘录未保留；共享验收文档缺少验收前完整 projection/binding snapshot，因此只能证明误选文件新增的 80 个 stable ID 已精确删除、数量恢复且无新增绑定或 ownership 残留，不能证明全量语义状态与验收前完全一致。该偏差已于 2026-08-06 由 Human 明确接受，不能将其改写为完整的全量恢复证据。完整验证结果见 [Sync Token 结构化异常诊断运行证据](../raw/2026-08-06-sync-token-structured-diagnostics-runtime-evidence.md)。
