---
title: Truncate Text 存储机制与 override 遮蔽语义
type: concept
created: 2026-08-24
updated: 2026-08-24
sources: [raw/2026-08-15-truncate-text-storage-and-override-research.md]
topic: Sketch 运行时
tags: [sketch-api, truncate, line-break-mode, override, text-style, stability]
status: current
context: 2
---

# Truncate Text 存储机制与 override 遮蔽语义

Sketch 的单行省略号截断由文本图层段落样式中的 `lineBreakMode` 持久化，不是独立的 Sketch 文档字段，也不属于 Instance override。其行为边界、遮蔽路径与原生操作安全边界依据[Truncate Text 存储机制与 Instance override 行为调研](../raw/2026-08-15-truncate-text-storage-and-override-research.md)。

## 存储载体与写入方式

- truncate 的持久化位置是 `text layer.style.textStyle.encodedAttributes.paragraphStyle.lineBreakMode`。值 `3`、`4`、`5` 分别表示头部、尾部和中部省略号；序列化时会与 attributed string run 合并为单一 run 副本。
- 公共 JS API 与 `.sketch` 文件格式 schema 都没有独立的截断字段。
- `setLineBreakMode(0)` 表示 word-wrap。由于 `0` 是默认值，序列化时该键会消失；因此“设回 word-wrap”和“落盘时没有该键”语义等价。
- 修改既有段落样式时，应从现有值执行 `mutableCopy`，只设置 `lineBreakMode`。用默认段落样式整体重建会丢失原字典中的其他字段，已实测导致行高丢失。

## Instance override 的遮蔽边界

Instance override 的公共字段与副本中的全量 `overrideName` 扫描均未发现段落或截断条目。textStyle override 的本质是 Shared Text Style ID 指针替换，因此 truncate 由 Master 图层属性承载，不能通过独立 override 表达。

- 当 override 值不等于 Master 的绑定样式时，Instance 会退化为多行换行，truncate 被遮蔽；Master 侧的 `lineBreakMode` 仍然存在于落盘快照中。
- 将 override 值改回 Master 绑定样式后，truncate 恢复。
- 公共 API `override.reset()` 清除 `_textStyle` override 条目，与改回 Master 值语义一致：渲染恢复，落盘 overrideValues 中对应条目消失，Master 属性不变。
- 逐字段修改 `textSize`、`textWeight` 或颜色期间，单行省略号保持有效，Master 的 `lineBreakMode` 不变。遮蔽只发生在 textStyle 指针切换这一条路径上。
- 字宽没有独立的 override 入口，只能通过 textStyle 指针切换实现，因此改变字宽可能进入 truncate 被遮蔽的路径。
- `textSize` 与 `textWeight` 赋值只接受字符串；传入数字可能静默失效。

## 原生脚本安全边界

遍历 Instance 派生层结构曾三次经 CocoaScript FFI 桥触发崩溃，包括两次 SIGBUS 和一次 `NSInvalidArgumentException` 转 SIGABRT。插件脚本应只对显式选中的 Text layer 原生对象进行操作，禁止遍历派生层结构。相关验证执行通道、Cloud 落盘核对与视觉判定方法见[Sketch 自动化验证操作手册](sketch-automation-verification-playbook.md)。

此外，不应通过 `sketchtool run-script` 批量删除 Shared Styles；该操作曾导致 Sketch Beta Automation 连接退出。

## 与多行截断的关系

`lineBreakMode` 的语义是单行截断，不能扩展为固定高度多行的末行省略号。多行需求应采用内容改写路线，并结合[多行文本截断可行性结论](multiline-text-truncation-feasibility.md)中的 `adjustToFit` 测量与二分算法；该路线需要额外处理原文恢复、行数参数化和混合样式保留。

## 环境与验证限制

以上 live 实验基于 Sketch 2026.3 Beta build 233880 与 macOS 27.0 beta（26A5406e），正式版尚未复核。Sketch MCP 的 `get_screenshot` 按 layer ID 约有 15 分钟缓存，连续变更应改用 PNG 导出与逐字节比对。Cloud 文档核对时应只读复制缓存 zip 并解包，不调用 `doc.save()`。
