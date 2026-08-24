---
class: material
ingested: false
metadata: ~
---

# Truncate Text 存储机制与 Instance override 行为调研

时间: 2026-08-14 至 2026-08-15（含 M4 复核）
来源: T2 Truncate Text 调研与插件实施（M0-M4）。完整方案见仓库 `docs/superpowers/plans/2026-08-15-truncate-text-plugin.md`，原始证据见 `docs/superpowers/evidence/2026-08-15-truncate-text-research-artifacts/`。
环境口径: 全部 live 实验基于 Sketch 2026.3 Beta build 233880 + macOS 27.0 beta（26A5406e），正式版未复核。

## 存储机制

- truncate（单行省略号截断）的持久化载体是 text layer 自身的 `style.textStyle.encodedAttributes.paragraphStyle.lineBreakMode`（NSLineBreakMode 3=头部 4=尾部 5=中部；序列化时与 attributedString run 合并为单一 run 副本）。公共 JS API 与 .sketch 文件格式 schema 均无独立截断字段。
- `setLineBreakMode(0)`（word-wrap）在落盘序列化时该键直接消失（0 为默认值，序列化只写非默认键），因此"设回 word-wrap"与"无该键"落盘等价。
- 用 `NSParagraphStyle.defaultParagraphStyle().mutableCopy()` 整体重建 paragraph style 会丢弃原字典全部键——这是 Automate 插件 Truncate Text 行高丢失的根因。安全写法是取既有值 mutableCopy 后仅 setLineBreakMode。

## Instance override 与遮蔽

- Instance override 字段面（公共 API 13 项 property + 副本全量 overrideName 扫描）无任何 paragraph/截断条目；textStyle override 是 Shared Text Style ID 指针替换。truncate 无法、也不需要经 override 表达，由 Master 图层属性承载。
- override 值 ≠ Master 绑定样式时，Instance 渲染退化为多行换行、truncate 被遮蔽（落盘快照显示 Master 层 lineBreakMode 全程在位而渲染失效）。
- override 值改回 Master 绑定样式，truncate 恢复。
- **清除 override 条目（公共 API `override.reset()`）与改回值语义一致**（M4 实测）：reset 后落盘 overrideValues 中 `_textStyle` 条目消失，渲染与基线逐字节一致，Master 侧属性零改动。
- 逐字段 override（textSize/textWeight/颜色）期间渲染保持单行省略号、Master 落盘 lineBreakMode 恒定——逐字段 override 是 truncate-安全的；遮蔽只发生在 textStyle 指针切换这一个动作上。改字宽无独立 override 入口，只能经 textStyle 指针切换，属遮蔽路径。
- textSize/textWeight 赋值只接受字符串（数字静默失效）。

## 崩溃教训

- 遍历 Instance 派生层结构经 CocoaScript FFI 桥三次引发崩溃：两次 SIGBUS（Sketch 与 sketchtool 成对崩溃报告），一次 `NSInvalidArgumentException` → SIGABRT（faulting thread 0 栈从 JavaScriptCore/Mocha/libffi `_MOFunctionInvoke` 进入 SketchModel/CoreText 字体描述符处理）。结论：插件脚本只对显式选中的 Text layer 原生对象操作，禁止遍历派生层。
- 不要通过 `sketchtool run-script` 批量删除 Shared Styles（曾导致 Sketch Beta Automation 连接退出）。

## 方法学附记

- `get_screenshot`（Sketch MCP）按 layer ID 有约 15 分钟缓存，连续变更观测必须走导出 PNG 链路；逐字节比对可替代目测判定渲染恢复。
- Cloud 文档落盘核对：定位 CloudDocuments 缓存文件，只读复制为 zip 解包比对，不调 `doc.save()`。
