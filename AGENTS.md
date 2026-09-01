# OpenInput（智能输入小窗）

macOS 原生悬浮输入面板应用：为单行输入框（地址栏、聊天框、邮件主题行等）提供舒适的小窗编辑体验。菜单栏常驻（LSUIElement，无 Dock 图标），编辑完成后按 Return 把文本粘贴回原输入框。XcodeGen 生成式工程，SwiftUI + AppKit 混编，Swift 6 并发。

## 2026-09-01 菜单栏完成态：已在 Mac 落地

源码已按全局菜单栏完成态接上：菜单含真实状态的开机自启动、隐藏图标、打开主窗口；独立轻量恢复主窗口；隐藏图标或再次打开时出示该窗口。输入小窗仍是点外面就关的唤出工具，不能当恢复面。

开机自启主路径走 MacKit；LaunchAgent 回退只留在本应用内，且不会自动重装。待系统批准不得显示成已开启。

本机已覆盖安装 1.1.1 (6)，找回窗已点到。公开更新三种网络结果与开机自启重新登录未测。改、评审或排查菜单栏、隐藏图标、开机自启、再次打开或恢复窗口前**必读** [菜单栏、隐藏图标与恢复窗口](docs/MENU_BAR_LIFECYCLE_GUIDE.md)（不读会把输入小窗当成恢复面，或隐藏图标后找不到应用）。禁止一次藏多个应用的图标。

## 当前交付边界与数据处理

**本应用以 Developer ID 自分发方式正式对外发布。**首次安装必须从公开 Release 下载已签名、公证并装订票据的拖拽安装镜像；已安装用户必须通过 Sparkle 的公开更新源获取经过 EdDSA 签名的更新包。不得把构建目录里的应用、裸压缩包或未公证产物当作可交付版本。

- 保存的数据：成功注入的历史文本、应用自动弹出记忆，以及窗口和功能偏好（含是否自动听写、听写语言、替换词）；均仅保存于这台 Mac 的本地存储，用户可在应用设置中管理历史和应用记忆。
- 当前未发现的行为：不上传或同步上述内容，也不建立网络连接。辅助功能权限只用于识别目标输入位置和将用户确认的文本粘贴回目标应用；麦克风只用于把用户说的话在本机转成文字。提交时的顺手清理若用到苹果端侧语言模型，也只在本机运行，且仅当用户机器本身已启用该能力时才会走；普通国行账号默认走不到这一档。若后续增加网络、同步、遥测、账号或第三方服务，必须先重新核对这段说明与隐私声明，不能沿用「纯本机」结论。
- 改发布、签名、公证、更新源或版本号前，**必须先读并落实** [签名、公证与分发指南](../_standards/workspace-docs/swift-docs/macos-signing-notarization-distribution.md)，否则会发出无法安装或无法更新的版本。发布由 `scripts/publish-release.sh` 统一执行：它归档并导出 Developer ID 应用、提交公证、装订票据、制作 DMG、生成 Sparkle 更新清单，把首装包与清单一并发到源码仓公开 Release（禁止另建更新仓），并以匿名下载复核。版本展示号和内部构建号同时递增；内部构建号是更新判定的权威。

通用工程规范：[Swift 规范](../_standards/swift.md)

## 代码约定

- XcodeGen 工程：`project.yml` 是唯一真实来源，改工程配置后必须重跑 `xcodegen generate`；生成的 `.xcodeproj` 不手改、不提交手工改动。
- 技术栈：SwiftUI 主体 + AppKit 补窗口/事件监听/AX；`KeyboardShortcuts` 负责全局热键；菜单栏生命周期与开机自启三态按需引用 MacKit（Core / LaunchAtLogin / Lifecycle），更新检查继续用 Sparkle，不要接 MacKitUpdater。
- 共享可变状态统一 `@MainActor @Observable final class` + 单例（`.shared`）；跨线程回调一律 `DispatchQueue.main.async` 桥回 MainActor，禁止在 Carbon/AX 回调里直接 `Task { @MainActor }`（会 SIGSEGV，见 HotkeyService）。音频采集类禁止标 MainActor，tap 回调禁止对每个缓冲区 `Task { @MainActor }`（前者会 SIGTRAP 闪退，后者会乱序并拖垮听写），见 [语音听写知识库](docs/VOICE_INPUT_KNOWLEDGE_BASE.md)。
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

Linux 开发机无法执行上述构建。菜单栏完成态的真机步骤见 [菜单栏、隐藏图标与恢复窗口](docs/MENU_BAR_LIFECYCLE_GUIDE.md) 文末。

## 文档导航

- `docs/INPUT_PANEL_KNOWLEDGE_BASE.md`：改、评审或排查小窗显隐、定位、提交/取消、边框焦点态、热键呼出，或听写开关在小窗里的接线前**必读**。不读会把提交改成直接注入、隐藏时漏停听写，或在麦克风授权窗弹出时把小窗关掉。
- `docs/VOICE_INPUT_KNOWLEDGE_BASE.md`：改、评审或排查语音听写、麦克风授权、提交时自动清理、「还原上次清理」、听写语言或端侧模型前**必读**。不读会接到云端识别、在旧系统上硬编听写、漏掉正式包麦克风声明，或把清理做成按钮。
- `docs/FOCUS_INJECTION_KNOWLEDGE_BASE.md`：改、评审或排查目标输入框捕获、锚点定位、粘贴注入或「还原上次清理」读焦点框前**必读**。不读会弄错坐标系或覆盖用户已经改过的原文。
- `docs/AUTO_SHOW_KNOWLEDGE_BASE.md`：改、评审或排查按应用记忆自动弹出、抑制与防抖、应用记忆读写前**必读**。不读会在听写授权窗或清理注入期间误关/误开小窗。
- `docs/HISTORY_KNOWLEDGE_BASE.md`：改、评审或排查历史记录持久化、搜索过滤、小窗内历史浏览或设置页管理前**必读**。不读会把听写清理后的稿与原文历史写乱。
- `docs/MENU_BAR_LIFECYCLE_GUIDE.md`：改、评审或排查菜单栏菜单、开机自启动、隐藏图标、再次打开应用或恢复主窗口前**必读**。不读会把输入小窗当成恢复面，或隐藏图标后留下找不到的后台应用。
- `docs/PREFERENCES_KNOWLEDGE_BASE.md`：改、评审或排查偏好存储、旧键迁移、登录启动、菜单栏图标显隐或设置页各页签（含语音）前**必读**。不读会把听写开关键名写散，或漏掉与麦克风按钮共用的那一项。
- `docs/ACCESSIBILITY_GUIDE.md`：改、评审或排查辅助功能权限、坐标转换、Observer 生命周期，以及焦点/自动弹出/注入相关代码前**必读**。不读会在无权限时把锚点算错，还原清理时也读不到焦点框。
- `docs/OPERATIONS_GUIDE.md`：构建、安装、启动、看日志、正式发布或按用户路径做运行验证前**必读**。不读会用未公证包当交付，或漏测听写授权与提交清理。
- `docs/APP_ICON_DESIGN.md`：生成、修改或评审应用图标前**必读**。不读会把图标做成常见便笺样式，小尺寸无法辨认。

## 领域地图（doc-init）

<!-- 覆盖度复核基线：2026-08-08 · 源码指纹 扫描 44 文件 / Swift 17（排除 .build 与 DerivedData）/ 0 子模块 · 基线提交 7e29002 -->

| 领域 | 入口锚点 |
|------|---------|
| 输入小窗（含热键呼出） | OpenInput/UI/InputPanel/, OpenInput/Services/HotkeyService.swift |
| 语音听写与提交清理 | OpenInput/Services/SpeechDictationService.swift, OpenInput/Services/TextRefinementService.swift, OpenInput/UI/Settings/VoiceSettingsView.swift |
| 焦点捕获与文本注入 | OpenInput/Services/FocusTracker.swift, OpenInput/Services/TextInjector.swift |
| 应用记忆与自动弹出 | OpenInput/Services/AutoShowMonitor.swift, OpenInput/Services/AppMemoryStore.swift |
| 历史记录 | OpenInput/Services/HistoryStore.swift, OpenInput/UI/History/ |
| 偏好设置与登录启动 | OpenInput/Services/PreferencesStore.swift, OpenInput/Services/LaunchAtLoginService.swift, OpenInput/Services/AccessibilityPermission.swift, OpenInput/UI/Settings/ |
| 菜单栏与恢复窗口 | OpenInput/App/OpenInputApp.swift, OpenInput/App/AppDelegate.swift, OpenInput/App/RecoveryWindowController.swift, OpenInput/UI/Recovery/RecoveryWindowView.swift |
| 数据模型 | OpenInput/Models/ |
