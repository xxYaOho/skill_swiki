---
title: Truncate Text 存储机制与 override 遮蔽语义
type: concept
created: 2026-08-15
updated: 2026-08-15
sources: [raw/2026-08-15-truncate-text-storage-and-override-research.md]
topic: Sketch 运行时
tags: [sketch-api, truncate, line-break-mode, override, symbol-instance, sketch-2026-3]
status: current
context: 2
---

# Truncate Text 存储机制与 override 遮蔽语义

Sketch 2026.3 Beta 文本截断的持久化机制与 Symbol Instance override 的交互结论（正式版未复核），是 `plugins/truncate-text` 插件全部设计约束的依据。依据：[Truncate Text 存储机制与 Instance override 行为调研](../raw/2026-08-15-truncate-text-storage-and-override-research.md)。

## truncate 存储在图层段落属性里

- 载体是 text layer 的 `style.textStyle.encodedAttributes.paragraphStyle.lineBreakMode`（3=头部 / 4=尾部 / 5=中部省略号）。公共 JS API 与文件格式 schema 均无独立截断字段。
- `setLineBreakMode(0)` 落盘时键直接消失（0 为默认值，序列化只写非默认键），"设回 word-wrap"与"无该键"落盘等价——这是移除命令精确还原的机制基础。
- 用 `defaultParagraphStyle().mutableCopy()` 整体重建段落样式会丢弃全部既有键（Automate 插件行高丢失的根因）；安全写法是对既有值 mutableCopy 后仅改 lineBreakMode。

## Instance override 遮蔽语义

truncate 由 Master text layer 承载，不经 override 表达（override 字段面无任何 paragraph 条目，textStyle override 是 Shared Style ID 指针替换）。遮蔽规则：

- Instance 的 textStyle override 指向 ≠ Master 绑定样式的其他样式期间，truncate 被遮蔽（渲染退化为多行换行），Master 层 lineBreakMode 在位但失效；任何仅写 Master 图层属性的实现都无法避免。
- **恢复路径有两条且语义一致（实测）**：override 值改回 Master 绑定样式，或对 override 条目调 `reset()` 直接清除（落盘条目消失，渲染逐字节复原）。
- 逐字段 override（textSize / textWeight / 颜色）truncate-安全；遮蔽只发生在 textStyle 指针切换。字宽无独立 override 入口，只能走指针切换，因此属于遮蔽路径。
- 陷阱：textSize / textWeight 只接受字符串赋值，数字静默失效。

## 派生层遍历会崩掉 Sketch

遍历 Instance 派生层结构经 CocoaScript FFI 桥三次引发真实崩溃（两次 SIGBUS + 一次 `_MOFunctionInvoke` 路径的 `NSInvalidArgumentException` → SIGABRT，Sketch 与 sketchtool 成对崩溃报告在案）。插件脚本只应操作显式选中的 Text layer 原生对象；同理不得经 `sketchtool run-script` 批量删 Shared Styles。与 [Sketch 资产运行时特性](sketch-asset-runtime-characteristics.md) 中"构建/安装/运行三状态"一样，这是从真实故障里固化的边界。

## 观测方法

- `get_screenshot`（Sketch MCP）按 layer ID 缓存约 15 分钟，连续变更观测走导出 PNG 链路；逐字节比对可替代目测判定"渲染是否复原"。
- Cloud 文档落盘核对只读复制解包，不调 `doc.save()`。
