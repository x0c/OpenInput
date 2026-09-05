# OpenInput 辅助功能（AX）机制 Guide

## 文档定位

本 Guide 覆盖 OpenInput 依赖 macOS 辅助功能（Accessibility）能力的三块公共机制及其代码入口：

1. **权限检查**：应用如何确认、请求「辅助功能」授权。
2. **坐标转换**：AX 左上原点坐标系与 AppKit 左下原点坐标系的换算规则；两种屏幕坐标混合使用必然出错。
3. **AXObserver 生命周期**：系统级 / 应用级元素获取、焦点属性读取、通知订阅/退订顺序。

不覆盖的内容：面板定位决策（见 INPUT_PANEL KB）、自动弹出触发判定细节（见 AUTO_SHOW KB）、锚点捕获回退链细节（见 FOCUS_INJECTION KB）。这些机制在多个领域（焦点捕获、自动弹出、注入失败引导）被重复依赖，因此单独成 Guide。

## 机制定位

OpenInput 是辅助功能重度应用：

- **捕获目标输入框**（`FocusTracker`）：需要读 `kAXFocusedApplicationAttribute`、`kAXFocusedUIElementAttribute`、`kAXSelectedTextRange`、`kAXBoundsForRange`、`kAXPosition/Size/Parent/Role/Description/Title/Value/NumberOfCharacters` 等属性。
- **自动弹出**（`AutoShowMonitor`）：需要 AXObserver 订阅 `kAXFocusedUIElementChanged`、`kAXFocusedWindowChanged`、`kAXSelectedTextChanged` 通知，并在回调里取焦点元素与角色。
- **权限状态 UI**（设置页）：需要检查 `AXIsProcessTrusted()` 显示授权状态，缺权限时引导到系统设置。

## 核心入口

### 1. 权限检查（AccessibilityPermission.swift）

```swift
enum AccessibilityPermission {
    static var isTrusted: Bool           // AXIsProcessTrusted()
    static func requestIfNeeded() -> Bool // AXIsProcessTrustedWithOptions(prompt)
    static func openSystemSettings()      // 打开辅助功能设置页（三跳回退）
}
```

- `isTrusted` 只是同步查询，**不会弹授权框**。首次授权流程：应用启动后设置页/自动弹出逻辑发现 `isTrusted == false` → 用户触发 `requestIfNeeded()` 或手动到系统设置。
- `openSystemSettings()` 用 URL scheme 依次尝试打开辅助功能权限页（macOS 版本间的系统设置路径有差异，代码里做了三次回退）。
- 系统设置 → 隐私与安全性 → 辅助功能 → 勾选 OpenInput。

### 2. 坐标转换（FocusTracker.axToCocoa）

macOS Accessibility API 返回的所有位置/尺寸（`kAXPosition`、`kAXSize`、`kAXBoundsForRange`）都在**左上原点屏幕坐标系**（屏幕顶部为 y=0）；而 AppKit 的 `NSWindow.frame`、`NSEvent.mouseLocation`、`NSScreen` 用**左下原点坐标系**。两者不换算直接用，面板会翻转到屏幕上半部分错误位置。

```swift
private func axToCocoa(_ axRect: CGRect) -> CGRect {
    let maxY = NSScreen.screens.map(\.frame.maxY).max() ?? 0
    return CGRect(
        x: axRect.origin.x,
        y: maxY - axRect.origin.y - axRect.height,
        width: axRect.width,
        height: axRect.height
    )
}
```

- 必须用**所有屏幕中 y 最大的屏幕**的 maxY 作为基准（多屏时单屏基准会产生偏移）。
- 一旦转换，后续 Apple 绘制/定位全用 AppKit 坐标，不再转回 AX。

### 3. AXObserver 生命周期

`AutoShowMonitor` 是唯一使用 AXObserver 的模块：

```swift
// attach（挂到 pid 对应应用）
var observer: AXObserver?
let callback: AXObserverCallback = { _, _, _, refcon in ... DispatchQueue.main.async }
AXObserverCreate(pid, callback, &observer)
AXObserverAddNotification(observer, appElement, name, refcon)  // 对 3 个通知名循环调用
CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)

// detach
AXObserverRemoveNotification(...)
CFRunLoopRemoveSource(CFRunLoopGetMain(), ...)
axObserver = nil; observedPID = nil
```

- AXObserverCreate 每个应用 pid 单独创建；切到新前台应用时先 detach 旧 pid 再 attach 新 pid。
- **通知名固定三枚**：`kAXFocusedUIElementChanged` / `kAXFocusedWindowChanged` / `kAXSelectedTextChanged`；订阅内容变化时要用 `AXObserverRemoveNotification` 逐个摘除再重建。
- 回调线程不在 MainActor 下：**必须 `DispatchQueue.main.async` 桥回**，禁止 `Task { @MainActor }`（SIGSEGV，见输入小窗知识库 §6 与 HotkeyService 注释）。

## 使用约束（OpenInput 特定规则）

- **AI 易错点**：所有 AX 属性名用 Apple 常量（`kAX*`），**不要**用字符串字面量写死（`"AXRole"` 等，Spell-correct 厉害的模型容易写错）。代码中保留了两个例外字符串（`AXSearchField`/`AXURLField` 等），仅用于补系统常量缺失，不得扩散。
- **AI 易错点**：AX 属性取值是 `CFTypeRef`，必须 `CFGetTypeID(...) == AXValueGetTypeID()` 校验后再 `AXValueGetValue`，不能直接 `as! ` 任意转（崩溃/随机值）。
- **禁止**在无权限时执行 AX 读取——所有 AX 调用前先 `AccessibilityPermission.isTrusted` 门控（FocusTracker/ AutoShowMonitor 的首道 guard）。
- 权限变更通过 NSWorkspace 在前台应用 onChange 重新检查，没有持续轮询权限本身。

## 领域中引用

- [FOCUS_INJECTION_KB](FOCUS_INJECTION_KNOWLEDGE_BASE.md)：锚点捕获的回退链与 `anchorFromElement` 判定树，坐标转换主消费方。
- [AUTO_SHOW_KNOWLEDGE_BASE.md](AUTO_SHOW_KNOWLEDGE_BASE.md)：通过 AXObserver 自动弹出触发。
- [INPUT_PANEL_KB](INPUT_PANEL_KNOWLEDGE_BASE.md)：面板定位消费 `captured?.anchorRect`。

## 待补充

- macOS 各版本 AX 行为差异的实测记录（尤其在 Chrome 上 `kAXSelectedTextChanged` 的可靠性）。
- 权限被应用杀等异常场景的策略（当前是静默 fallback 到鼠标位置）。

<!-- 该文档整理/压缩于 2026-09-05 -->
