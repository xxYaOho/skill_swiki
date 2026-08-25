---
class: evidence
ingested: false
metadata: ~
---

# Sync Token 结构化异常诊断运行证据

## 执行基线

- `DIAGNOSTICS_BASELINE`: `3e676b34a90e4d8b6ce2531b9be85e40b520d2e6`
- 插件版本真源：`plugins/sync-token/package.json`
- 基线版本：`1.2.1`
- 设计：`docs/superpowers/specs/2026-08-05-sync-token-structured-diagnostics-design.md`
- 实施计划：`docs/superpowers/plans/2026-08-06-sync-token-structured-diagnostics.md`

## 基线验证

验证时间：`2026-08-06T09:58:22+0800`

```bash
pnpm --filter sync-token test
pnpm --filter sync-token typecheck
```

结果：

- Vitest：20 个测试文件通过，249 个测试通过。
- TypeScript：通过，无诊断。

## 自动化与安装产物

实施完成后的单插件验证：

```bash
pnpm --filter sync-token test
pnpm --filter sync-token typecheck
pnpm --filter sync-token build
```

结果：

- Vitest：23 个测试文件、391 个测试通过。
- TypeScript：通过，无诊断。
- Build：通过。
- `plugins/sync-token/package.json` 版本为 `1.2.1`。
- dist manifest、installed manifest 与 5 个正式 command 的 SHA-256 一致。
- 正式 bundle 不包含临时 fatal harness identifier 或 adapter。
- 覆盖安装后重启 Sketch Beta；schema 2 特有 GUI 与日志行为证明运行进程已加载新 bundle，而不只依赖文件校验和。

全仓验证曾执行并通过：

```bash
pnpm typecheck
pnpm test
pnpm build
```

其中 tooling 测试为 8 个测试通过。最终提交前再次运行完整命令，结果记录在本节末尾。

## 正式产品路径

目标文档：

- 名称：`dev-test.sketchcloud`
- document ID：`5630E959-4EC4-481D-B6A3-9401ACA9C96F`
- 原始 slot 只保留在任务运行时内存中，未写入本文、日志或截图。
- 原始 slot 已直接写回并 readback；presence 与原生字符串 byte-for-byte 相同。

### Invalid reference

安装后的 `Sync Current` 产生 schema 2 事件：

```text
eventId: D133B19D-5AB5-4A6A-B937-0EC0993FA251
failureId: F1
command: sync-current
attempt: 1
code: missing-color-target
phase: input
operation: verify
stage: input.resolve.reference
assertion: target-exists
recovery: fix-source
complete: false
skipped: 2
notAttempted: 1
committedWrites: 0
```

Human 根据真实 modal 截图确认：

- Problems 首位展开并直接显示首因、受影响 token、缺失 target 与修复建议。
- Not Synced 默认折叠；长 token 名称仅纵向滚动，没有横向溢出或内容重叠。
- 详情文本可选择复制；Return 可关闭 modal。
- GUI 的 `D133B19D-5AB5-4A6A-B937-0EC0993FA251/F1` 与日志逐字对应。

Retry 重新读取来源并写入独立事件。首次 Retry 为 `C76A10B6-6D7C-4355-9585-C6B4CB717EB0`、`attempt: 2`，不是复用原事件；后续人工重复触发也分别产生独立 event ID。

### Complete no-op

安装后的合法 no-op 事件：

```text
eventId: C8DFD740-DB66-4BC6-BE32-8F0D90E33D52
command: sync-current
complete: true
added: 0
updated: 0
unchanged: 1
skipped: 0
notAttempted: 0
committedWrites: 0
```

Human 确认 GUI 为 `Unchanged 1`、无 Problems、无 Retry。`lastSynced` 只在该 complete 结果后更新；invalid 结果不更新。

### Add Slot 文件选择器

正式 `Add Slot...` 文件选择器选择任务 invalid fixture 后产生：

```text
eventId: 3FCA9AD1-E610-470A-AA07-8385342E7C25
failureId: F1
command: add-slot
code: missing-color-target
complete: false
notAttempted: 1
committedWrites: 0
```

这证明只有 `invalid-token-field` 或可识别 input diagnostic 的文件可进入正式结果 modal，而不是退回通用 alert；完全无关 JSON 的拒绝边界由自动测试覆盖。

## Fatal 与日志降级

fatal 场景仅在任务专属 disposable 文档与独立 harness/log root 中运行，不触碰 `dev-test.sketchcloud`：

- disposable document ID：`58272A3D-86CF-4D15-B5AC-9D57DC0E4D8C`
- 任务临时路径：`.tmp-sync-token-diagnostics-acceptance/fatal-disposable.sketch`

- Policy Fatal：无 Retry，明确 local collection 已恢复，但 returned asset 仍不可信。
- Recovery Fatal：rollback diagnostic 为首因，原 runtime cause 为次因；不把当前资产描述为已恢复。
- Unknown Exception：使用结构化 fallback，保留 phase/stage，不虚构 mismatch。
- Receipt Full：显示完整 `eventId/F#`。
- Receipt Partial：只说明日志保留部分技术详情，不显示误导性的完整引用。
- Receipt Dropped：明确显示 `Technical details were not written to the log.`，无失效引用。

这些结果证明 production diagnostic factory、finalizer、schema 2 formatter 与 modal presenter 在 CocoaScript/AppKit 中的传播和呈现合同，不证明 production 原生异常条件可稳定触发。disposable 文档已关闭，临时 bundle、fixture 与日志根目录已删除；正式 bundle 中无 harness 标识。

限制：fatal modal 由 Human 通过会话截图逐项确认，但截图文件、临时日志中的 event/failure ID 与日志摘录没有在清理前落盘，因此本文只记录已确认行为，不把该段描述为原计划要求的完整可复查证据。

## 误选文件与资产恢复

正式 `Add Slot...` 验收时，操作者先误选了 `orca2sketch.json`。这是验收操作误选，不是产品错误，也不是可忽略的测试噪声。日志证据：

```text
F75004FD-37FF-4F76-8CB6-8DF3B8F9EE26  add-slot     80 added / 9 unchanged / committedWrites 80
2D600791-49D2-4CFF-9833-2A6BE4B26AD6  sync-current 89 unchanged / committedWrites 0
```

误选后资产数量由验收前的 `61 / 27 / 22` 变为 `118 / 39 / 33`。恢复时先从误选前后增量确定 80 个新增稳定 ID，再逐项要求唯一、local、无文档图层绑定；不按名称推断，也未使用 `sketchtool run-script`。按依赖顺序删除：

1. 11 个 Text Style，读回 `22`。
2. 12 个 Layer Style，读回 `27`。
3. 57 个 Swatch，分为 `10 / 10 / 10 / 10 / 10 / 7` 六批，逐批读回，最终为 `61`。

最终读回：

```text
Swatches: 61
Layer Styles: 27
Text Styles: 22
新增 80 个稳定 ID残留: 0
新增 Shared Style 文档图层绑定: 0
新增 Swatch 文档图层直接绑定: 0
unknown ownership: 0
```

随后运行的 invalid fixture 为 preflight 失败，`committedWrites: 0`，没有新增资产。原始 slot 已 byte-for-byte 恢复。

限制：验收前完整资产 projection/binding 快照原文没有落盘，因此共享文档未证明已恢复到验收前的完整语义状态。可证明的是已按前后增量精确删除误选新增的 80 个 stable ID、数量恢复且没有新增 ID 或新增绑定残留；这些证据不能替代全量 stable ID、ownership、canonical projection 与 binding ID 的前后比较。任务临时 invalid fixture 已删除。

## 验收偏差处置

`2026-08-06T23:04:24+0800`，Human 在已知以下证据缺口后明确接受验收偏差并授权收尾：

- 共享文档缺少验收前完整 projection/binding snapshot，未证明全量语义恢复。
- fatal harness 的截图文件、event/failure ID 与临时日志摘录未保留。

该批准允许以明确限制提交本次 evidence，不把上述缺口改写成 Task 14 或 Task 16 已完整通过，也不改变产品实现、自动测试、正式 bundle 和已保留真实运行证据的结论。

## 最终验证

最终验证时间：`2026-08-06T23:04:24+0800`

```bash
pnpm --filter sync-token typecheck
pnpm --filter sync-token test
pnpm --filter sync-token build
pnpm typecheck
pnpm test
pnpm build
git diff --check
```

结果：

- 单插件 typecheck：通过。
- 单插件 test：23 个测试文件、391 个测试通过。
- 单插件 build：通过，生成 manifest 声明的 5 个正式 command。
- 全仓 typecheck：通过。
- 全仓 test：tooling 8 个测试与 Sync Token 391 个测试通过。
- 全仓 build：通过。
- package、dist manifest、installed manifest 版本均为 `1.2.1`。
- 5 个 dist/installed command SHA-256 逐项一致。

## 隐私与运行边界

- 不在本文、日志或截图中记录 `NSUserDefaults` 原始 slot blob。
- 不记录用户文档路径、完整 token 内容、原生 Cocoa 对象或 stack trace。
- `dev-test.sketchcloud` 仅在通过原始 slot 值无损写回探针后用于正式产品路径验收。
- fatal fault injection 只在独立可丢弃 Sketch 文档中运行。
- `orca2sketch.json` 的 80 个新增资产来自操作者误选文件，不归因于产品行为异常。
