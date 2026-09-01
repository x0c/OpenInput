# OpenInput 运行与验证 Guide

## 文档定位

OpenInput 是 macOS 原生应用（SwiftUI + AppKit + XcodeGen 生成工程），无独立后端。本 Guide 覆盖：构建、安装、启动、日志查看与运行验证套路。涉及「打开应用」「给某个输入框注入文本」「自动弹出」等用户行为的调试时，按本文件的操作顺序执行。

## 构建

### 前置

- macOS 14.0+（project.yml `deploymentTarget: 14.0`）。语音听写与端侧清理只在 macOS 26+ 生效，工程用 Xcode 26 编译，并把端侧模型框架弱链接，避免旧系统启动崩溃。
- Xcode 26 命令行工具
- XcodeGen 已安装（`brew install xcodegen`）

### 构建命令（Debug）

```bash
cd /Users/geraltgraham/Codes/OpenInput
xcodegen generate
xcodebuild -scheme OpenInput -configuration Debug -derivedDataPath .doc-init-dd build
```

> `.build/` 是 SPM 解析目录，**不要**提交；`.doc-init-dd/` 是调试构建产物目录（在 .gitignore 中已排除）。

### Release / 发布构建（签名）

发布用自定义签名与公证流程，见「发布」一节；日常开发一律 Debug 构建即完成验证。

## 2. 安装与启动

### 直接启动（开发）

```bash
open .build/Build/Products/Debug/OpenInput.app
```

### 视为正式应用

- 拖到 `/Applications`（或 `cp -R` 拷贝）
- 首次运行需要到系统设置 → 隐私与安全性 → 辅助功能 勾选 OpenInput
- 语音听写另外需要麦克风权限；第一次点小窗麦克风（或打开「下次自动听」）时系统会询问。正式安装包若拿不到麦克风而调试包可以，先核对发布权限声明，不要只查系统设置。
- 菜单栏出现 text.cursor 图标即启动成功

### 启动行为

- LSUIElement（菜单栏应用，不 Dock 图标）。
- 启动后没有面板、只有菜单栏图标；按 `⌥⌘I` 全局热键呼出输入小窗。
- 设置项在菜单栏 → 设置。隐藏图标后会出现带标题的恢复主窗口（不是输入小窗）；再次点应用图标也会出示它。
- 菜单栏完成态的真机步骤见 [菜单栏、隐藏图标与恢复窗口](MENU_BAR_LIFECYCLE_GUIDE.md)。Linux 开发机不能编译，不得把源码改完写成已验证。

## 3. 日志与排查

OpenInput 用 `os.Logger`：

| 子系统 | Category | 记录内容 |
|---|---|---|
| `com.x0c.openinput` | `AppMemoryStore` | 应用记忆读取/写入失败 |
| `com.x0c.openinput` | `HistoryStore` | 历史读取/写入失败 |
| `com.x0c.openinput` | `听写` | 听写启动/失败、语言 |
| `com.x0c.openinput` | `听写清理` | 端侧校对超时、失败、熔断 |

日志查看（Console.app 或命令行）：

```bash
log show --last 30m --predicate 'subsystem == "com.x0c.openinput"' --style compact
```

常见排查起点：

- 面板没弹出：检查辅助功能权限 → `InputPanelController` 的流程日志（暂无 log 输出，靠行为判断）；先确认热键是否被系统占用（键盘设置）。
- 历史/记忆异常：看 `AppMemoryStore`/`HistoryStore` category 的 error。
- 乱码/文本不进：注入链路在 `TextInjector`，无日志输出（当前类没有 log 调用），需在代码中插入 log 排查。
- 听写没出字：先看麦克风授权与「听写」分类日志；旧系统应灰掉而不是崩溃。
- 提交后稿子没被顺手清理：看「听写清理」分类；国行机器上这是预期降级，不是故障。

## 4. 运行验证套路

### 4.1 冒烟验证

```
1. 启动 app → 菜单栏图标出现
2. ⌥⌘I → 面板显示，编辑首行字符可见
3. 输入文本 → 回车 → 文本出现在目标应用输入框
4. 再次 ⌥⌘I → 面板收起
```

### 4.2 注入验证

- 打开「备忘录」新笔记，点输入区 → ⌥⌘I → 输入多行文本 → Return → 文本应原样进入备忘录。
- 若面板定位偏移或文本丢失 → 检查辅助功能权限。

### 4.3 历史验证

1. 提交一段文本 → 小窗内 ↑ 弹出历史列表 → 选中旧文本 → 提交应直接粘贴。
2. 设置页「历史」页签：搜索、删除、清空。

### 4.4 自动弹出验证

1. 设置页「自动弹出」勾选某应用 → 聚焦该应用输入框 → 面板应自动弹出。
2. 手动关闭一次（esc）→ 该应用自动弹出被关闭（记忆）。
3. 再次打开 → 重新自动弹出。

### 4.5 语音听写验证

完整步骤与降级口径见 [语音听写知识库](VOICE_INPUT_KNOWLEDGE_BASE.md) §7。最少要覆盖：第一次麦克风授权后小窗还在、对着说话能出字、回车插入、开关打开后下次唤出自动听。旧系统只验按钮灰掉。

## 5. 发布

OpenInput 是正式自分发应用：源码仓公开 Release 的 DMG 用于第一次安装，应用内更新使用同一 Release 里的签名 ZIP 和更新清单（appcast 作为 Release 附件，更新源为 `releases/latest/download/appcast.xml`；源码仓已公开，禁止另建独立更新仓，2026-08-17 已从 `x0c/OpenInput-updates` 迁回本仓）。**改发布、签名、公证、更新源或版本号前必须先读**工作区《签名、公证与分发指南》，否则可能发出无法打开或无法自动更新的版本。

发布前在 `project.yml` 同时提升展示版本和严格递增的内部构建号；然后运行：

```bash
scripts/publish-release.sh
```

脚本会完成 Developer ID 归档导出、签名校验、苹果公证、票据装订、DMG 制作、Sparkle 更新包与清单签名、源码仓 Release 发布，以及匿名下载检查。公证处于苹果侧排队时必须让脚本在可脱离会话的后台进程中继续运行，并保留日志和提交编号；不得把“已提交”表述成“已公证”。

源码仓 Release 是首装和更新产物的唯一可访问入口：同一版本的 DMG、ZIP 与 appcast 都挂在该 Release，更新清单用 `releases/latest/download/appcast.xml` 匿名读取。生成清单时下载地址前缀必须以 `/` 结尾，否则 Sparkle 会拼出缺少版本标签的失效地址。重跑发布前先查询 Release 是否已有同名资产；已有时直接做匿名下载验证，不得重复上传。

## 6. 常见问题（FAQ）

| 问题 | 原因 / 解决 |
|---|---|
| 启动后没有图标 | 先看是否主动隐藏了菜单栏图标；隐藏后应出现恢复主窗口。否则检查 Gatekeeper（右键打开） |
| 隐藏图标后找不到应用 | 从「应用程序」或 Spotlight 再打开，应出现恢复窗口；不要把输入小窗当恢复面 |
| ⌥⌘I 没反应 | 热键被占用 / 未授权辅助功能（设置页有权限条）|
| 文本注入总是失败 | 目标应用无辅助功能权限（不可由本 app 自查，需用户在系统设置授权）|
| 面板不自动弹出 | 应用记忆被关闭（esc 过一次）/ 总开关关闭 |
| 听写按钮是灰的 | 系统低于 macOS 26，这是覆盖范围，不是故障 |
| 点了麦克风立刻闪退 | 录音回调被标成主线程专属；已作为禁止项写入语音知识库。若再现，先看崩溃栈是否仍是 `_dispatch_assert_queue_fail` |
| 提交后没有「还原上次清理」 | 清理没改过字，或端侧模型不可用只走了规则层且规则层也没改 |
| 编译报错 BuildE 错误 | 先 `xcodegen generate` 再 build；SPM 包网络失败时重试 |

## 7. 待补充

- macOS 各版本窗口层级差别（`.floating` 在成组空间/全屏的实测）。

<!-- 该文档由 doc-init 生成于 2026-08-08；定位：AI 涉及构建、启动、日志排查、运行验证时的操作手册 -->
