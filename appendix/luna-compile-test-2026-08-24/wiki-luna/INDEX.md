# INDEX

> [!IMPORTANT]
> Headline 2 为主题聚类, 无主题内容默认放在 Headline 1 中. 同主题条目达到 3 条时, 为它们创建独立主题.
> 每页一行, 先查阅编译后的知识, 按需查阅源材料:
> - [title](<file>.md) | <context>k | <一句话描述> | tag, tag

## Sync Token 同步设计

- [Sync Token Text Style 同步设计](sync-token-text-style-sync.md) | 1k | v2 textStyle 五字段合同、字重映射与 detached Text create-or-update 语义 | sync-token, text-style, shared-style, sketch-api
- [Sync Token 扁平 key 颜色引用设计（已废弃）](sync-token-flat-key-color-references.md) | 1k | 旧 `@<flat-key>` 颜色引用设计, 已被完整路径引用取代, 保留供溯源 | sync-token, color-reference, swatch, superseded
- [Sync Token 完整路径颜色引用设计](sync-token-full-path-color-references.md) | 2k | `@/` RFC6901 引用、canonical 资产身份、Swatch registry 与 item 事务 | sync-token, color-reference, rfc6901, transaction, registry
- [Sync Token 本地资产所有权设计](sync-token-local-asset-ownership.md) | 2k | getLibrary 判定 local/foreign/unknown, M3A-D 安装态与 M3B wrapper identity 修正 | sync-token, ownership, library, swatch, rollback

## Sync Token 诊断与反馈

- [Sync Token 结构化异常诊断设计](sync-token-structured-diagnostics.md) | 4k | cause-first 诊断合同、Failure ID、fatal envelope、Problems / Not Synced Modal 与 schema 2 日志 | sync-token, diagnostics, failure-id, rollback, ndjson, appkit, verification
- [Sync Token 同步结果 Modal 设计](sync-token-result-modal.md) | 1k | 逐项 SyncResult 与 NSPanel 四分组结果反馈、Retry 行为 | sync-token, appkit, nspanel, ui, sync-result
- [Sync Token 独立 NDJSON 日志设计](sync-token-ndjson-logging.md) | 1k | 独占日志文件、10 MiB 容量合同、NSDistributedLock 与路径脱敏 | sync-token, logging, ndjson, nsdistributedlock, capacity

## Sketch 运行时

- [Sketch 资产运行时特性](sketch-asset-runtime-characteristics.md) | 2k | 快照 wrapper、名称/身份/所有权三分、事务写入顺序与安装生命周期 | sketch-api, runtime, wrapper, stable-id, transaction, sketch-2026-3
- [Sketch corners 派生字段只读导致 Radius 重同步失败](sync-token-radius-readonly-corners.md) | 1k | `hasRadii` 只读抛 TypeError, 解法为 canonical projection + 写入 allowlist | sync-token, sketch-api, corners, readonly, radius
- [Sketch 自动化验证操作手册](sketch-automation-verification-playbook.md) | 2k | 执行通道分层、Cloud 文档验证链路、公共 API 陷阱、视觉判定与稳定性红线 | sketch-api, automation, sketchtool, mcp, verification
- [Library Token 到 Local 的四条替换通道](sketch-library-token-replacement.md) | 2k | override 复合 id 与 swatchValue 形态、fill/border 直挂 swatch、颜色遮蔽与并发防护 | sketch-api, override, swatch, library, symbol-instance, mirror-token
- [Sketch 文本 sizing 模型](sketch-text-sizing-model.md) | 2k | textBehaviour 废弃、MSLayerText 图层级 sizing 枚举语义与 adjustToFit 测量 oracle | sketch-api, text, sizing, mslayertext, adjusttofit, sketch-2026-3
- [多行文本截断可行性结论](multiline-text-truncation-feasibility.md) | 2k | lineBreakMode 单行语义封死原生路线、内容改写二分算法与产品化差距 | sketch-api, truncate, line-break-mode, multiline, spike, decision
- [Truncate Text 存储机制与 override 遮蔽语义](truncate-text-storage-and-override-semantics.md) | 2k | lineBreakMode 持久化位置、textStyle override 遮蔽与 reset 语义、原生脚本崩溃边界 | sketch-api, truncate, line-break-mode, override, text-style, stability

# 未分组

- [独立插件发布与自动发现设计](independent-plugin-release-and-discovery.md) | 1k | 插件目录自治的版本真源、bundleName 自动发现与安全安装边界 | installer, release, workspace, versioning
- [AppKit 批量选择 Modal 模式](appkit-batch-selection-modal.md) | 1k | NSAlert accessoryView 批量选择列表、坐标/滚动布局与默认值策略 | appkit, nsalert, nspopupbutton, ui, mirror-token
