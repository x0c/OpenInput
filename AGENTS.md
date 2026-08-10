# OpenInput（智能输入小窗）

macOS 原生悬浮输入面板应用：为单行输入框（地址栏、聊天框、邮件主题行等）提供舒适的小窗编辑体验。菜单栏常驻（LSUIElement，无 Dock 图标），编辑完成后按 Return 把文本粘贴回原输入框。XcodeGen 生成式工程，SwiftUI + AppKit 混编，Swift 6 并发。

## 当前交付边界与数据处理

**本应用以 Developer ID 自分发方式正式对外发布。**首次安装必须从公开 Release 下载已签名、公证并装订票据的拖拽安装镜像；已安装用户必须通过 Sparkle 的公开更新源获取经过 EdDSA 签名的更新包。不得把构建目录里的应用、裸压缩包或未公证产物当作可交付版本。

- 保存的数据：成功注入的历史文本、应用自动弹出记忆，以及窗口和功能偏好；均仅保存于这台 Mac 的本地存储，用户可在应用设置中管理历史和应用记忆。
- 当前未发现的行为：不上传或同步上述内容，也不建立网络连接。辅助功能权限只用于识别目标输入位置和将用户确认的文本粘贴回目标应用；若后续增加网络、同步、遥测、账号或第三方服务，必须先重新核对这段说明与隐私声明，不能沿用「纯本机」结论。
- 改发布、签名、公证、更新源或版本号前，**必须先读并落实** [签名、公证与分发指南](../_standards/workspace-docs/swift-docs/macos-signing-notarization-distribution.md)，否则会发出无法安装或无法更新的版本。发布由 `scripts/publish-release.sh` 统一执行：它归档并导出 Developer ID 应用、提交公证、装订票据、制作 DMG、生成 Sparkle 更新清单、发布到公开更新仓，并以匿名下载复核。版本展示号和内部构建号同时递增；内部构建号是更新判定的权威。

通用工程规范：[Swift 规范](../_standards/swift.md)

## 代码约定

- XcodeGen 工程：`project.yml` 是唯一真实来源，改工程配置后必须重跑 `xcodegen generate`；生成的 `.xcodeproj` 不手改、不提交手工改动。
- 技术栈：SwiftUI 主体 + AppKit 补窗口/事件监听/AX；`KeyboardShortcuts` SPM 包负责全局热键。
- 共享可变状态统一 `@MainActor @Observable final class` + 单例（`.shared`）；跨线程回调一律 `DispatchQueue.main.async` 桥回 MainActor，禁止在 Carbon/AX 回调里直接 `Task { @MainActor }`（会 SIGSEGV，见 HotkeyService）。
- 偏好键与默认值成对集中声明（`PreferencesKeys` / `AppMemoryKeys`），禁止在使用处散落字面量键；键名统一「域.名」点分命名。
- 用户可见文案一律走 `String(localized:)` + `Localizable.xcstrings` 本地化资源，禁止硬编码中文。
- 所有错误路径（文件 IO、JSON 编解码、登录启动注册）必须写失败处理，不得 `try!` / 静默吞掉。
- 注释与日志用中文（`os.Logger`）。
- macOS 蓝框消除已落地：面板主输入框是自绘 `NSTextView`（无系统 focus ring），搜索框走 `.textFieldStyle(.plain)` + 自有焦点态描边（`@FocusState` overlay stroke），面板焦点态用自绘边框光晕（`BorderOverlayView`）；新增任何可聚焦控件必须保持这一约定。

## 验证

```bash
xcodegen generate
xcodebuild -scheme OpenInput -configuration Debug -derivedDataPath .doc-init-dd build
```

启动验证：`open .doc-init-dd/Build/Products/Debug/OpenInput.app`（或覆盖安装到 /Applications 后启动）。运行依赖「辅助功能权限」：首次使用需在 系统设置 → 隐私与安全性 → 辅助功能 授权。

## 文档导航

> 以下文档在涉及对应领域的开发、评审或排查时先读取。

- `docs/INPUT_PANEL_KNOWLEDGE_BASE.md`：小窗生命周期与显隐决策、定位锚定、提交/取消分流、面板自绘边框与焦点态、热键呼出
- `docs/FOCUS_INJECTION_KNOWLEDGE_BASE.md`：目标输入框捕获（AX 焦点解析与回退链）、锚点坐标转换、⌘V 剪贴板注入时序、辅助功能权限
- `docs/AUTO_SHOW_KNOWLEDGE_BASE.md`：按应用记忆自动弹出、AXObserver/点击/轮询触发判定、抑制与防抖、应用记忆读写
- `docs/HISTORY_KNOWLEDGE_BASE.md`：历史记录持久化、去重置顶、搜索过滤、小窗内历史浏览与设置页管理
- `docs/PREFERENCES_KNOWLEDGE_BASE.md`：偏好存储与旧键迁移、登录启动注册（SMAppService/LaunchAgent）、设置页各页签
- `docs/ACCESSIBILITY_GUIDE.md`：辅助功能（AX）机制——权限检查、坐标转换、Observer 生命周期；改焦点/自动弹出/注入相关代码时必读
- `docs/OPERATIONS_GUIDE.md`：构建、安装、启动、日志、正式发布与运行验证套路
- `docs/APP_ICON_DESIGN.md`：生成、修改或评审应用图标前必读，避免图标退化为常见便笺样式并保持小尺寸识别度

## 领域地图（doc-init）

<!-- 覆盖度复核基线：2026-08-08 · 源码指纹 扫描 44 文件 / Swift 17（排除 .build 与 DerivedData）/ 0 子模块 · 基线提交 7e29002 -->

| 领域 | 入口锚点 |
|------|---------|
| 输入小窗（含热键呼出） | OpenInput/UI/InputPanel/, OpenInput/Services/HotkeyService.swift |
| 焦点捕获与文本注入 | OpenInput/Services/FocusTracker.swift, OpenInput/Services/TextInjector.swift |
| 应用记忆与自动弹出 | OpenInput/Services/AutoShowMonitor.swift, OpenInput/Services/AppMemoryStore.swift |
| 历史记录 | OpenInput/Services/HistoryStore.swift, OpenInput/UI/History/ |
| 偏好设置与登录启动 | OpenInput/Services/PreferencesStore.swift, OpenInput/Services/LaunchAtLoginService.swift, OpenInput/Services/AccessibilityPermission.swift, OpenInput/UI/Settings/ |
| 数据模型 | OpenInput/Models/ |
