# OpenInput 运行与验证 Guide

## 文档定位

OpenInput 是 macOS 原生应用（SwiftUI + AppKit + XcodeGen 生成工程），无独立后端。本 Guide 覆盖：构建、安装、启动、日志查看与运行验证套路。涉及「打开应用」「给某个输入框注入文本」「自动弹出」等用户行为的调试时，按本文件的操作顺序执行。

## 构建

### 前置

- macOS 14.0+（project.yml `deploymentTarget: 14.0`）
- Xcode 16+ 命令行工具
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
- 菜单栏出现 text.cursor 图标即启动成功

### 启动行为

- LSUIElement（菜单栏应用，不 Dock 图标）。
- 启动后没有面板、只有菜单栏图标；按 `⌥⌘I` 全局热键呼出输入小窗。
- 设置项在菜单栏 → 设置。

## 3. 日志与排查

OpenInput 用 `os.Logger`：

| 子系统 | Category | 记录内容 |
|---|---|---|
| `com.x0c.openinput` | `AppMemoryStore` | 应用记忆读取/写入失败 |
| `com.x0c.openinput` | `HistoryStore` | 历史读取/写入失败 |

日志查看（Console.app 或命令行）：

```bash
log show --last 30m --predicate 'subsystem == "com.x0c.openinput"' --style compact
```

常见排查起点：

- 面板没弹出：检查辅助功能权限 → `InputPanelController` 的流程日志（暂无 log 输出，靠行为判断）；先确认热键是否被系统占用（键盘设置）。
- 历史/记忆异常：看 `AppMemoryStore`/`HistoryStore` category 的 error。
- 乱码/文本不进：注入链路在 `TextInjector`，无日志输出（当前类没有 log 调用），需在代码中插入 log 排查。

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

## 5. 发布

发布命令（本地签名 + 公证可选；发布流程由脚本或手动完成）。

- 当前版本的版本号维护在 `project.yml`（`MARKETING_VERSION`）+ Info.plist。
- 生成 Xcode 工程后构建 Release：
  ```bash
  xcodegen generate
  xcodebuild -scheme OpenInput -configuration Release -derivedDataPath .build/release build
  ```

> 暂未接入 GitHub Actions / 公证自动流程；手工发布收尾（打包 dmg / 上传）属于工程外操作。

## 6. 常见问题（FAQ）

| 问题 | 原因 / 解决 |
|---|---|
| 启动后没有图标 | 检查是否被 Gatekeeper 拦截（右键打开）；确认启动方式 |
| ⌥⌘I 没反应 | 热键被占用 / 未授权辅助功能（设置页有权限条）|
| 文本注入总是失败 | 目标应用无辅助功能权限（不可由本 app 自查，需用户在系统设置授权）|
| 面板不自动弹出 | 应用记忆被关闭（esc 过一次）/ 总开关关闭 |
| 编译报错 BuildE 错误 | 先 `xcodegen generate` 再 build；SPM 包网络失败时重试 |

## 7. 待补充

- 公证（notarize）与 DK 签名流程尚未在本项目执行过，先加入开发者团队后再补。
- macOS 各版本窗口层级差别（`.floating` 在成组空间/全屏的实测）。

<!-- 该文档由 doc-init 生成于 2026-08-08；定位：AI 涉及构建、启动、日志排查、运行验证时的操作手册 -->