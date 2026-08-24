---
class: material
ingested: false
metadata: ~
---

# Sync Token 结构化异常诊断设计

## 背景

Sync Token 已能在结果 modal 和独立 NDJSON 日志中报告失败，但现有诊断只保留 `code + message`。这会产生两类排错盲区：

- preflight 失败时，大量 `not-attempted` 条目可能排在真正的输入错误之前。用户先看到“未尝试”，却看不到阻断同步的首因。
- Swatch、Layer Style 和 Text Style 的创建、更新与回滚包含多个复合断言。任一断言失败都可能收敛为 `post-write verification failed` 或 `post-create verification failed`。GUI 无法解释具体原因，日志也只能定位到资产，不能定位到失败阶段和字段。

本设计建立一份由异常产生点提供的结构化诊断。GUI 用它回答“哪里错、为什么、怎么处理”；日志用它定位 command、attempt、phase、stage、assertion、source pointer 和字段差异。两者消费同一事实源，不从错误字符串反推原因。

## 目标

- GUI 首屏优先显示真正的错误，不让 `not-attempted` 淹没首因。
- GUI 使用用户可理解的原因、差异和处理建议，不暴露 CocoaScript 内部对象。
- 日志使用稳定机器字段定位失败边界，不依赖 `message` 文本。
- 对字段写后不一致，记录安全且有界的 expected/actual。
- 对 identity、ownership、binding、cleanup 和 rollback 失败，记录具体 assertion 与恢复结果。
- 未知 bridge exception 仍能落入结构化 fallback，且明确标为未知，不伪造原因。
- GUI 中的短错误编号可与同一次日志 failure 对应。

## 非目标

- 不改变 token parser 的接受范围或引用合同。
- 不改变 preflight 零写入门禁、资产写入顺序、运行时 fail-fast、单项 rollback 或 `lastSynced` 条件。
- 不引入失败后继续写入、全文件 dry-run 或自动修复。
- 不记录完整 token、完整 style projection、document path、原生 Cocoa 对象或 stack trace。
- 不增加日志查看器、结果导出、搜索或历史记录。
- 不在本轮处理插件版本升级与发布。

## 设计原则

1. **事实在源头产生。** Parser、preflight 和各 writer 在知道失败事实的位置构造 diagnostic。Presenter 不解析 `Error.message`。
2. **根因与后果分离。** 真实 diagnostic 是 cause；`not-attempted` 是 consequence。GUI 分区展示，日志只展开 cause。
3. **面向用户与开发者分层。** GUI 展示原因、差异和下一步；日志保留稳定定位字段和受限技术细节。
4. **未知就明确未知。** 无法确定字段或原因时使用 `unexpected-runtime-error`，不得把推测写成处理建议。
5. **事务事实必须准确。** 单项 rollback 成功不等于整次同步零写入。GUI 和日志必须同时保留 `committedWrites` 与失败项 rollback outcome。
6. **诊断不能影响同步。** 构造、格式化或记录 diagnostic 失败时使用最小 fallback；logger 仍是 best-effort，不能改变同步结果。

## 结构化诊断合同

### 基础类型

```ts
type DiagnosticPhase =
  | 'input'
  | 'preflight'
  | 'runtime'
  | 'rollback'
  | 'command'

type DiagnosticOperation =
  | 'parse'
  | 'index'
  | 'create'
  | 'update'
  | 'verify'
  | 'cleanup'
  | 'restore'
  | 'read'
  | 'write'
  | 'present'

type RecoveryKind =
  | 'fix-source'
  | 'check-font'
  | 'resolve-duplicate'
  | 'remove-unsupported-asset'
  | 'retry'
  | 'inspect-log'
  | 'stop-and-recover-document'

type DiagnosticScalar = string | number | boolean | null

interface DiagnosticMismatch {
  field: string
  expected?: DiagnosticScalar
  actual?: DiagnosticScalar
}

interface RollbackDiagnosticState {
  attempted: boolean
  outcome: 'not-needed' | 'succeeded' | 'failed' | 'unknown'
  stage?: string
  code?: string
}

interface SyncResultCounts {
  added: number
  updated: number
  unchanged: number
  skipped: number
}

interface CauseDiagnostic {
  kind: 'cause'
  code: string
  phase: DiagnosticPhase
  operation: DiagnosticOperation
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

type SyncDiagnostic = CauseDiagnostic | NotAttemptedDiagnostic
```

`code`、`stage` 和 `assertion` 是稳定机器标识：

- `code` 表示失败类别，例如 `invalid-color-reference`、`field-mismatch`、`asset-identity-mismatch`。
- `stage` 表示代码执行边界，例如 `text-style.update.verify`。
- `assertion` 表示该边界内失败的具体不变量，例如 `style-projection-equal`、`returned-ownership-local`、`binding-ids-stable`。

`message` 保留为兼容字段和未知异常 fallback。Modal 和 logger 不得根据它推导 `code`、recovery 或 mismatch。`not-attempted` 是明确的 consequence union member，不要求虚构 recovery、assertion 或 mismatch。

### 构造边界

新增集中式 diagnostic factory，只负责以下工作：

- 校验 plain object、primitive 和短数组边界。
- 把原生值先转为普通 primitive；无法安全转换时省略 actual，而不是序列化 wrapper。
- 对 known error 生成稳定字段。
- 对 unknown exception 生成 `unexpected-runtime-error`，保留调用方提供的静态 phase、operation、stage。Factory 可在内层 try 中读取 `String(error)`；该转换或任一 native getter 再次抛错时，最外层只使用调用点传入的 typed static context 和固定 message 构造 primitive-only fallback，不再访问原错误。Parser、writer、rollback 和 command 各自保留真实 phase/stage；统一使用 `inspect-log / Unexpected error.`。Factory 自身不得向同步调用方抛错。

Factory 不维护模块顶层 `RegExp`、`Set` 或原生对象。错误 catalog 使用函数内 plain object 或直接分支，遵循 CocoaScript bundle 约束。

### Failure ID

每次 sync attempt 在最终化结果时，把同一 `SyncItemResult` 中除 `not-attempted` 外的 diagnostics 组成一个 problem，并按 problem 展示顺序分配事件内短编号 `F1`、`F2`。编号不持久化、不跨 Retry 稳定，也不参与同步身份。Modal 为 problem card 显示该编号；日志 failure 写入同一编号和有界 diagnostics 数组，供用户把 GUI 与日志对应。

`not-attempted` 不分配 failure ID。

每次 attempt 或 attempt 外 command error 另生成 best-effort `eventId`。优先使用 Foundation UUID 并立即转为普通字符串；UUID bridge 失败时退化为 timestamp、command 和 attempt 组成的 correlation value，并记录 `eventIdSource: fallback`。fallback 可能重复，不得被当作唯一身份。`eventId` 只用于 GUI/log 对照，不参与资产身份、去重或事务判断。logger receipt 证明写入成功后，GUI 才显示 `eventId/F#`；command error 没有 problem 时只显示 `eventId`。

## 初始错误分类

所有 `stage`、`assertion`、`code` 和 `recovery` 必须由导出的 typed constants 定义并在 producer、presenter 和测试间复用。禁止在调用点拼接近义名称。本文统一使用 `returned-ownership-local`，不再使用 `ownership-local`。

### Input

Parser 不再把所有非法 leaf 压成 `invalid token leaf`。它按已识别 discriminator 提供字段级事实：

| Code | Assertion / detail | GUI 处理建议 |
| --- | --- | --- |
| `invalid-color-reference` | `reference-rfc6901`; expected 完整 `@/` pointer，actual 为有界原值 | 修正原始 JSON 引用 |
| `missing-color-target` | `target-exists`; targetPointer | 补充或修正目标 color token |
| `non-color-target` | `target-is-color`; targetPointer | 把引用改为 color token |
| `invalid-token-field` | 字段名与 constraint；允许 expected/actual | 修正原始 JSON 字段 |
| `unknown-token-node` | source pointer 与 node category | 移除未知节点或补全 token leaf |
| `ambiguous-token-file` | `root-format-exclusive` | 只保留一种根格式 |

输入诊断只报告可由现有 parser 证明的事实。不得根据 asset name 猜测 token 类型。

### Preflight

| Code | Assertion / detail | GUI 处理建议 |
| --- | --- | --- |
| `duplicate-document-target` | `local-name-unique`; actual 为本地同名数量 | 删除或重命名重复本地资产 |
| `asset-ownership-unavailable` | `ownership-readable` | 查看日志并检查异常资产 |
| `migration-unsupported` | `style-type-supported`; expected/actual style type | 手动移除不支持的历史资产 |

Library asset 继续被排除，不作为 duplicate、update 或 rollback target。诊断增强不得改变 ownership 判定。

### Runtime

Swatch、Layer Style、Text Style 的 create/update 统一拆分以下 assertion。不同 collection 使用各自 stage 前缀。

| Assertion | 说明 |
| --- | --- |
| `input-field-applied` | setter 当场抛错；记录正在写入的字段和安全 primitive，不增加回读 |
| `returned-ownership-local` | create 返回资产 ownership 必须为 local |
| `stable-id-present` | 新建或既有资产必须有 stable ID |
| `stable-id-unique` | 最新 collection 中 stable ID 必须唯一 |
| `collection-position-stable` | 需要保持 index 的更新后位置必须不变 |
| `asset-name-equal` | 最新资产名称必须等于 canonical asset name |
| `style-type-equal` | Shared Style 类型必须符合目标类型 |
| `style-projection-equal` | canonical public projection 必须相等；记录 owned fields 的最小 diff |
| `swatch-binding-equal` | Text/Shadow 引用的 Swatch stable ID 必须匹配 current-run registry |
| `binding-ids-stable` | 既有绑定实例集合 identity 不得漂移 |
| `binding-style-equal` | 每个重新绑定实例的 canonical projection 必须一致 |

复合条件必须按现有短路顺序拆开，一次只报告第一条已证明失败的 assertion。拆分不得增加原生 collection 或 wrapper getter 的调用次数，也不得为了收集更多错误继续读取失败断言后的原生字段。Setter throw 使用 `input-field-applied`；静默写入不一致只能由现有最终 plain projection 产生 `style-projection-equal`。若 projection 不一致，只从已经取得的 plain canonical projection 计算有限 diff：

- Text Style 只比较 `fontFamily`、`fontSize`、`fontWeight`、`lineHeight`、`kerning` 和 text Swatch identity。
- Swatch 只比较 `name`、canonical color 和 stable ID / collection position 合同。
- Layer Style 只比较现有 canonical projection；复杂数组不写入完整 expected/actual，只写首个差异字段、元素索引和有界 primitive，或写 count/hash 摘要。

无法从 projection 证明“字体未安装”时，GUI 只显示“Sketch 未保留指定字体”，处理建议为“检查字体名称与本机可用性”。`check-font` 不得被表述为已证明缺少字体，避免把名称错误、字重不匹配或 Sketch fallback 误判为未安装。

### Rollback 与 fatal error

可恢复的 runtime item failure 在 diagnostic 中记录：

```json
{
  "rollback": {
    "attempted": true,
    "outcome": "succeeded",
    "stage": "text-style.update.restore"
  }
}
```

以下判定保留现行 recoverable / hard-failure 语义：

| 场景 | Cleanup / restore | 结果 |
| --- | --- | --- |
| candidate apply、update verification 或 create identity/projection 失败 | 成功 | 普通 skipped problem；保持 fail-fast |
| update verification 失败 | 失败或无法确认 | fatal |
| create 失败 | cleanup 失败、出现 unknown delta 或无法恢复 collection identity | fatal |
| Layer/Text create 返回 foreign 或 unknown ownership | 即使 cleanup 成功 | fatal，保留现有 hard policy |
| 既有 target 在写入/恢复期间变为 foreign、unknown 或无法唯一定位 | 无法证明完整恢复 | fatal |

fatal 场景不能返回普通 `SyncResult`。实现使用 plain branded fatal envelope，不依赖跨 CocoaScript bundle 不可靠的 `instanceof`：

```ts
interface SyncFatalEnvelope {
  __syncTokenFatal: 1
  fatalKind: 'policy-fatal' | 'recovery-fatal'
  commandStage?: string
  diagnostic: CauseDiagnostic
  cause?: CauseDiagnostic
  confirmedProgress: {
    items: SyncItemResult[]
    counts: SyncResultCounts
    committedWrites: number
  }
  currentItem: {
    collectionKind: AssetCollectionKind
    sourcePath: string[]
    name: string
    mutationAttempted: boolean
    state: 'restored' | 'unknown' | 'partially-mutated'
  }
}
```

`runCommandStep()` 先用 plain property guard 识别该 envelope，只补 `commandStage`，不得用普通 `Error` 覆盖 diagnostic、cause 或内部 stage。普通异常继续使用现有包装行为。

fatal envelope 分为两类：

- `policy-fatal`：Layer/Text create 返回 foreign/unknown ownership，cleanup 已成功且 collection identity 已恢复，但现有 hard policy 仍要求停止。主 diagnostic 保留真实 `phase: runtime`、`operation: create`、create stage 和 `returned-ownership-local`；cleanup outcome 记录为 succeeded；`currentItem.state` 为 `restored`。不得伪造 rollback failure。
- `recovery-fatal`：cleanup、restore 或其 verification 失败。主 diagnostic 使用 `phase: rollback`、真实 cleanup/restore operation、stage 和 assertion；`cause` 保留最初 runtime diagnostic；`currentItem.state` 为 `unknown` 或 `partially-mutated`。

两类 envelope 都携带进入当前失败项之前的 confirmed progress。只有 `recovery-fatal` 使用 `recovery: stop-and-recover-document`；`policy-fatal` 使用 `inspect-log`，说明 cleanup 已成功但 ownership policy 不允许继续。

rollback/cleanup outcome 是原始 cause 的附属恢复状态，不产生第二个并列 problem。只有 recovery 自身失败并升级为 `recovery-fatal` 时，rollback diagnostic 才成为 fatal 主因；不得为收集第二条 assertion 越过现有短路点。

每个 writer 在抛出 fatal error 时附带本阶段抛错前已经确定的 item results。`syncDocument()` 只为报告合并“此前已完成阶段 + fatal writer confirmed progress”，不得把该快照返回为普通完成态，也不得借此继续同步。`committedWrites` 只表示此前已确认的 added/updated 数量，不表示当前失败资产的最终状态，也不表示文档总变更数。

命令层为两类 fatal 显示不同高严重度 GUI，均阻止 Retry。`policy-fatal` 说明“不安全的资产 ownership，cleanup 已完成，同步已停止”；`recovery-fatal` 说明“恢复失败，当前资产状态无法确认”，并建议先保留现有工作、查看日志和检查受影响资产，再由用户决定撤销、恢复或关闭文档。不得无条件建议关闭且不保存。命令层同时记录 `command-error` schema 2。不得把 fatal 描述成普通 skipped，也不得声称此前成功写入已回滚。

### Command error

Add Slot、Switch Slot 和 Sync Current 的现有步骤标签保留，并转换为稳定 stage。至少区分：

- `source.pick`
- `source.read`
- `source.parse-json`
- `slot.save`
- `sync.run`
- `last-synced.update`
- `result.present`

外围异常使用稳定 code，例如 `source-read-failed`、`json-parse-failed`、`slot-save-failed`、`result-presentation-failed`。未知异常使用 `unexpected-command-error`。GUI 提供与 stage 相符的简洁建议，日志保留脱敏 message。

## GUI 设计

### 信息架构

成功结果继续显示 Added、Updated、Unchanged，沿用现有 modal 行为。

失败结果改为原因优先：

```text
Sync stopped
1 problem stopped 10 later items. 73 earlier changes completed.

Problems                                              1  v
  [text] mono-body                         F1
         v2/display
         Sketch did not retain the requested font.
         Expected: Departure Mono
         Actual: PingFang SC
         Check the font name and local availability, then retry.

Not Synced                                           10  >
Added                                                57  >
Updated                                              16  >
Unchanged                                             5  >
```

失败 modal 的首屏规则：

1. `Problems` 固定排在首位并自动展开，只包含真实 diagnostics。
2. `Not Synced` 只包含 `not-attempted`，默认折叠。标题说明“N 项因上述问题未执行”，展开后才列 token；不重复同一句原因。
3. Added、Updated、Unchanged 保留独立计数和现有逐项明细，默认折叠。
4. 普通结果 modal 中，runtime 首因排在其他 runtime diagnostics 前；preflight 结果按 canonical source path 与 code 保持稳定顺序。preflight 与 runtime 不会在同一次正常 `SyncResult` 中并存。fatal rollback 使用独立高严重度 GUI，不进入该排序。
5. 同一资产的多条真实 diagnostics 合并为一个 problem card，但分别显示 assertion 对应的事实；failure ID 指向该 card。

Modal presenter 从 `code + recovery + mismatches` 做确定性映射。每张 problem card 最多包含：

- 用户可理解的原因。
- 资产名称和路径。
- 一组有界 expected/actual 差异。
- 一条处理建议。
- 可复制的短编号 `F#`。

GUI 不显示内部 stage、assertion、selector、Cocoa wrapper、完整原生 Error 或 stack。无法确定原因时，基础文案固定为“Sketch 在同步此资产时返回未知异常。”；只有 `DiagnosticLogReceipt` 证明对应 failure 已写入时才追加“请在日志中查找 eventId/F#”，否则追加“技术详情未写入日志”。

### 摘要语义

Modal header 必须准确说明本次尝试：

- `N problems stopped M later items.`
- 普通可恢复失败可显示 `K earlier changes completed.`，其中 K 等于 `committedWrites`。
- 失败项 rollback 成功时可说“Failed item was restored.”。
- rollback 未尝试或结果未知时不显示恢复结论。
- fatal rollback 时显示“Recovery failed for this asset. Its current state is unknown.”，并另列此前 confirmed progress；不得把 confirmed progress 称为文档总影响。

不得使用“同步已全部回滚”“没有修改”这类无法由结果字段证明的文案。

### AppKit 边界

- 保持原生 `NSPanel`、固定宽度、纵向滚动、无横向滚动、adaptive colors 和可选择文本。
- 允许根据 problem 内容增加行高，但不改变 callback retention、Return/Escape、Retry 和 panel cleanup 合同。
- `Not Synced` 聚合只发生在 modal model，不删除 `SyncResult.items`，避免计数和其他调用方漂移。
- Retry 仍重新读盘并产生新 attempt；不复用上次 diagnostic。
- fatal rollback GUI 不提供 Retry。

## NDJSON 日志 schema 2

日志外层保留 schema 1 的现有字段并升级 `schema: 2`。每条记录增加运行时版本，以便区分 Sketch/CocoaScript 行为。`pluginVersion` 在运行时读取已安装 bundle manifest；manifest 版本继续由插件 `package.json` 生成，不新增硬编码版本真源。

```json
{
  "schema": 2,
  "timestamp": "2026-08-05T08:30:13.128Z",
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
          },
          "message": "Sketch did not retain the requested font family."
        }
      ]
    }
  ]
}
```

### 定位合同

开发者使用以下组合定位错误：

```text
command + attempt + source
phase + stage + assertion
collectionKind + sourcePointer + name
failureId + diagnostics[].code + mismatches + rollback
runtime versions
```

`stage` 和 `assertion` 必须能在仓库中直接 `rg` 到定义或测试。它们不包含动态文本。

fatal `command-error` 使用同一 runtime、failure 和 progress 结构：failure 保存 policy cause，或原始 runtime cause 与 rollback failure；`confirmedProgress` 只保存进入当前 item 前已确认的 counts 和 `committedWrites`；`currentItem` 按 fatal kind 记录 `restored`、`unknown` 或 `partially-mutated`。它继续是 command error，不进入普通 `SyncResult.failures`，不提供 Retry。

### 大小与隐私

```ts
type LogPointerLocator = string | {
  prefix: string
  suffix: string
  utf8Bytes: number
  fnv1a32: string
  truncated: true
}
```

日志投影中的 `sourcePointer`、`targetPointer` 和未来新增的任意 pointer 字段统一使用该 `LogPointerLocator` 规则；内存中的 `SyncDiagnostic` 继续保留完整 pointer，不能把截断 locator 回写为同步身份。

- 继续使用单事件 256 KiB、当前日志 5 MiB、单一备份 5 MiB、UTF-8 byte 计数和现有进程间锁。
- source 只记录 basename；不记录 document path、完整 source path、token 内容或 stack。
- 任意 pointer 在 8 KiB UTF-8 内完整保留。超限时日志改写为 `{ prefix, suffix, utf8Bytes, fnv1a32, truncated: true }`；fingerprint 按 pointer 的 UTF-8 bytes 计算，只用于排错定位，不参与 token identity 或安全判断。GUI 仍从内存中的完整 sourcePath 展示可滚动内容。
- 所有 message、expected 和 actual 字符串都执行现有绝对路径脱敏；相对 token name 不得被吞掉。
- 每个 problem 最多保留 8 条 diagnostics，每条 mismatch 最多保留前 8 项；每个 field、expected、actual 独立限长。复杂对象改为 count/hash 或省略。problem 增加 `omittedDiagnostics`，diagnostic 增加 `omittedMismatches`。
- 截断优先级固定为：外层固定字段、首因结构、fatal rollback 结构、其他真实 failure、mismatch 细节、message。首因 problem 不得整体丢弃，但其中所有动态字符串和 pointer 都按明确规则有界化；不得承诺无限长度原值完整保留。
- `not-attempted` 继续只记总数，不写入 failures；可增加按 collection 的有界计数，但本轮不是必需项。
- logger 失败继续静默丢弃本次记录，不影响 GUI、资产或 Retry。

日志写入返回不抛异常的 `DiagnosticLogReceipt`：`written`、`eventId`、`includedFailureIds`、`partiallyIncludedFailureIds`、`omittedFailureIds`。`runSyncAttempts()` 只把该 receipt 传给结果 presenter，不参与 completion、Retry 或 `lastSynced` 判断。Modal 仅在 `written: true` 且对应 ID 完整包含时提示“在日志中查找 eventId/F#”；problem 内部 diagnostics/mismatches 被截断时提示“日志仅保留部分技术详情”；日志丢弃或该 failure 被整体省略时明确说明技术详情未写入日志，不提供失效的交叉引用。

### 兼容策略

- schema 2 writer 保留 schema 1 外层字段语义，便于现有人工检索。
- 不在 `schema: 1` 下静默加入改变语义的字段。
- `SyncDiagnostic.message`、顶层 `diagnostics` 和 `errors` 在迁移期保留，由结构化 diagnostic 生成。
- 所有 producer 迁移完成后，Modal 与 logger 才切换为只消费结构化字段；禁止一半路径依赖 message、一半路径依赖 code。

runtime metadata 在 command boundary 只读取一次并转换为 plain strings。`pluginVersion`、`sketchVersion` 或 `apiVersion` 任一读取失败时省略该字段；不得让版本读取失败影响日志、GUI 或同步，也不得在 writer 内重复调用 bridge getter。

## 数据流

```text
parser / preflight / writer / rollback / command boundary
  -> diagnostic factory
  -> SyncResult items and fatal error envelope
  -> finalize causes, consequences, counts, failure IDs
  -> GUI presenter: cause-first model + recovery copy
  -> log presenter: schema 2 + bounded technical facts
```

同步数据流和事务顺序保持不变。新增 finalizer 只读取结果并派生 failure ID、Problems 与 Not Synced，不重新判断业务正确性。

## 实施边界

设计落地时按以下依赖顺序推进：

1. 扩展 diagnostic 类型、factory 和 schema 2 formatter，不改变 producer 行为。
2. 把 parser、`canAttemptSync()` eligibility gate 和 preflight 一起迁移到结构化 producer，修复首因排序。任何新增 input code 必须同步进入 gate 的 typed recognized-code catalog，确保 Add Slot 能进入结果 modal，而不是退回通用 alert。
3. 按 Swatch、Layer Style、Text Style 拆分 create/update verification assertions。
4. 结构化 rollback、cleanup 和 command fatal error。
5. 切换 Modal 为 Problems / Not Synced 模型，并切换 logger schema 2。
6. 完成自动化、临时 diagnostic harness、真实安装 bundle 和隔离 Sketch 文档验收。

阶段间允许短期保留 compatibility message，但任一可发布节点必须保证所有现有 producer 都能生成完整 fallback；不能出现 diagnostic 丢失。

## 自动化验收

### Diagnostic contract

- 每个 known failure 都有稳定 `code/phase/operation/stage/recovery`。
- 每个 stage/assertion 可在源码和测试中直接检索。
- code、stage、assertion 与 recovery 的映射使用穷尽测试；新增枚举值但未定义 GUI 文案或日志投影时 typecheck/test 必须失败。
- unknown exception 产生 `unexpected-*` fallback，不丢 phase/stage，不虚构 mismatch。
- 原生值、循环对象、getter exception 和无法序列化值不会让 diagnostic factory 抛出。
- 只有 `invalid-token-field`、没有 recognized record 的输入仍能通过 `canAttemptSync()` 进入 preflight 结果；完全无关 JSON 继续被 Add Slot 拒绝。

### Cause ordering and GUI model

- 1 个 input error 加 100 个 `not-attempted` 时，Problems 首项是 input error；Not Synced 为 100 且默认折叠。
- 1 个 runtime failure 加 499 个后续未执行项时，Problems 只有真实失败；不生成 499 张重复原因卡。
- fatal rollback 使用独立高严重度 GUI，不显示 Retry，并明确当前资产状态未知。
- 普通结果中 `committedWrites > 0` 时摘要明确此前已完成修改；fatal 只显示 confirmed progress，并把 current item 标为 unknown/partially-mutated。
- 同一资产已有的多条 diagnostic 合并为一张 card，保留各 assertion 且只给一个 failure ID；不得为收集额外 assertion 增加原生 getter 调用或越过既有短路点。
- 完全成功保持现有 Added、Updated、Unchanged 行为。

### Field-level verification

- Text Style 分别注入 fontFamily、fontSize、fontWeight、lineHeight、kerning、text Swatch mismatch，断言字段级 expected/actual。
- Swatch 分别注入 stable ID、index、name、color mismatch。
- Layer Style 分别注入 projection、binding、ownership 和 identity mismatch。
- create/update/cleanup/restore 每个复合断言都能得到唯一 stage/assertion。
- rollback succeeded/failed/unknown 与实际控制流一致。

### Log schema and bounds

- GUI failure ID、code、asset 与日志逐字对应。
- 每个 failure 可由 `phase + stage + assertion + sourcePointer` 定位。
- schema 2 保留原计数、attempt、source basename、committedWrites 和 notAttempted。
- 超限 pointer 产生稳定 prefix/suffix/byte count/fingerprint；不声称完整保留。
- 截断后的 problem/diagnostic/mismatch 分别带准确 omission 元数据；GUI 只引用 receipt 证明已写入的 failure ID。
- 超过 256 KiB 时输出仍是单行合法 NDJSON，首因和 fatal rollback 的结构不被整体丢弃，动态字段按 bounded locator/string 规则截断，所有 omission 计数准确。
- Unix、Windows、UNC、file URI 和 document/source path 脱敏；相对 token path 保留。
- lone surrogate、中文和其他多字节字符截断后仍可解析。
- logger 的锁竞争、stale lock、文件类型异常和磁盘失败继续不改变同步结果。

## 真实 Sketch 验收

必须构建并安装正式插件，核对 package、dist manifest、installed manifest 和正式 command bundle。真实已安装 command 只承担可稳定到达的产品路径验收：

1. 非法输入引用：GUI 首屏显示引用格式和修正建议；日志定位 input stage 与 sourcePointer。
2. 可由真实运行时稳定构造的普通 runtime failure：GUI 显示已证明的字段或 assertion；日志包含 stage 与 rollback outcome。若当前 Sketch 版本无法稳定触发，该项不作为正式 command gate。
3. runtime fail-fast：后续项目聚合到 Not Synced，计数准确。
4. Retry：重新读取文件并生成新 attempt，旧 failure ID 不跨 attempt 复用。

create ownership/identity、native setter 和 fatal restore 无法由合法产品输入稳定制造。它们使用两层直接验证：

1. Node fault-injection tests 对每个 ordered assertion、fatal policy、confirmed progress 和 current item state 做确定性覆盖。
2. 构建任务专属临时 diagnostic harness，复用正式 diagnostic factory、finalizer、Modal presenter、schema 2 formatter 和 command envelope；通过 test-only adapter 注入 ownership、setter 和 restore failures，在真实 CocoaScript/AppKit 中验证 envelope 传播、GUI、日志和生命周期。该 harness 使用独立 identifier、显式任务文档 ID 和任务专属日志根目录，不进入正式 manifest、dist 或 installed product bundle；验收后完整删除。

临时 harness 只证明诊断与展示链路，不冒充原生 failure 的生产复现。若未来自然复现某个 native failure，再补正式 command canary，不阻塞本方案验收。

每个场景截图确认首因首屏可见、长名称和差异文本不重叠、只有纵向滚动、文本可复制、Return/Escape 生命周期正确。receipt 证明写入成功且包含对应 problem 时，日志必须与截图中的 eventId/failure ID 和资产对应；日志被丢弃或截断时，GUI 必须显示相应降级状态。

验收不得使用用户业务文档，不得用 Node mock、dist checksum 或最小 MCP 探针替代真实 command。完成后只清理任务拥有的文档、fixture、日志根目录和 Automation 上下文。

## 成功标准

当一次同步失败时：

- 用户在 GUI 首屏能识别首因、受影响资产、已知差异、处理建议和实际影响范围。
- 日志 receipt 成功时，开发者能用同一 `eventId/F#` 在日志中定位 command/attempt、运行时版本、phase/stage/assertion、sourcePointer、字段差异和 rollback outcome；日志未写入时 GUI 不提供失效引用。
- GUI 与日志不依赖 message 文本推断事实。
- 新诊断不改变同步、回滚、Retry、日志容错和 `lastSynced` 的既有行为。
