# TinyTodo 架构说明 / Architecture Notes

## 目标

1 秒内看到待办；一次输入加回车记录；一次点击完成；历史永久可查；随时撤销。
所有能力都围绕"使用成本最低"设计，功能数量不是目标。

## 分层

```
main.swift / AppDelegate        AppKit 生命周期，主菜单、菜单动作
AppEnvironment                  组合根：数据库、仓储、视图模型、面板、菜单栏、快捷键
TinyTodoApp -> (no SwiftUI App) 使用纯 AppKit main，避免 SwiftUI 场景接管菜单栏
Window/                         NSPanel、屏幕管理、逐显示器帧记忆
Features/                       SwiftUI 视图 + @Observable 视图模型
Data/                           GRDB 数据库、迁移、仓储
Services/                       撤销、导入导出、开机启动
HotKey/                         KeyboardShortcuts + Carbon 冲突检测
Support/                        设置、日期分组、窗口几何、视觉背景
```

## 为什么窗口必须是 AppKit `NSPanel`

SwiftUI 的 `Window` 无法稳定地同时满足：始终置顶、加入所有 Spaces、全屏应用旁可见、
失焦不隐藏、逐显示器记住位置、无标题栏但可拖动。`FloatingPanelController` 直接控制：

```swift
styleMask: [.titled, .fullSizeContentView, .resizable, .closable, .nonactivatingPanel]
level: .floating            // "始终置顶"开启时；关闭时为 .normal
collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
hidesOnDeactivate = false
```

窗口内容为 `NSHostingView<PanelRootView>`；拖动由头部 `WindowDragArea`（`performDrag`）
和 `isMovableByWindowBackground` 共同提供。

## 线程与数据流

- 所有 SQLite 操作经由 `TodoRepository`，在 GRDB 的串行队列上执行；UI 不直接触碰 SQL。
- 待办列表：`ValueObservation.tracking { SELECT ... WHERE status = 0 ORDER BY sort_order }`
  在 main queue 推送，`TodoViewModel.items` 更新即刷新 SwiftUI。
- 历史与统计：变化时通过 `TodoRepository.storeDidChangeNotification` 通知视图模型重新查询
  （带 160ms 防抖），不做定时轮询。
- 写操作前先本地提交数据库，再发通知；失败通过 Toast 显示，不让 UI 处于假状态。

## 完成与历史

`status` 0/1 是唯一状态源；完成即 `status = 1, completed_at = now`，撤销即 `status = 0,
completed_at = NULL`。没有第二份历史表，因此不存在同步问题。历史查询永远带索引
（`completed_at`、`status, sort_order`），1 万条任务的分页查询在测试中 < 2s（实测 0.13s）。

## 撤销

`UndoService` 保存动作快照：完成（原 `sortOrder` 保留）、删除（整行快照，重新插入）、
排序（旧 id 顺序）、重命名（旧值）。⌘Z 与 Toast 上的「撤销」共用同一栈，深度 50。
撤销完成时使用 `position: .original` 回到原位置；历史页主动「恢复到待办」则追加到末尾。

## 中文输入法

输入控件是 `NSTextView` 子类（`FocusableTextView`），不是 SwiftUI `TextField`：

- `insertNewline`、`keyDown` 在提交前检查 `hasMarkedText()`；拼音组合期间回车只确认候选词。
- 粘贴内容含多行时拆分为多条待办，并去掉 `- `、`* `、`• `、`[ ]`、`- [x] ` 前缀。
- 提交后清空并保持第一响应者，支持连续输入。

## 测试策略

- 单元/集成：仓储、迁移（含 v1 库升级保历史）、导入导出、日期分组（含夏令时）、撤销栈、
  视图模型流程、真实 NSPanel 行为、输入控件回车/输入法/粘贴。
- UI：XCUITest 覆盖启动出窗、创建、完成、历史、设置；UI-test 模式下 `TestScreenPolicy`
  把面板与设置窗口放到非主显示器，避免占用用户当前屏幕；执行需要给测试运行器授权辅助功能权限。
- 性能/内存：`scripts/make_dmg.sh` 产出的 Release 构建实测 cold start ≈ 1s，
  `phys_footprint` ≈ 26 MB，空闲 CPU 0%。
