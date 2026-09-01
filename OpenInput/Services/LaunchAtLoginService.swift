import Foundation
import MacKitCore
import MacKitLaunchAtLogin
import ServiceManagement

/// 登录项注册：签名安装走 MacKit 的系统登录项；ad-hoc / DerivedData 才允许本应用内 LaunchAgent。
/// LaunchAgent 回退不得进公共库，也绝不能自动重装（会孵出卡住的程序坞图标）。
@MainActor
enum LaunchAtLoginService {
    private static let agentLabel = "com.x0c.openinput.launchagent"
    private static let systemService = MacKitLaunchAtLogin.LaunchAtLoginService()

    private static var agentPlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(agentLabel).plist")
    }

    typealias Status = LaunchAtLoginStatus

    static func currentStatus() -> Status {
        systemService.refresh()
        switch systemService.status {
        case .on:
            return .on
        case .needsApproval:
            return .needsApproval
        case .off:
            // 仅当系统登录项不可用、本机已有用户显式装过的 agent 时，才算开。
            return launchAgentInstalled ? .on : .off
        }
    }

    private static var launchAgentInstalled: Bool {
        FileManager.default.fileExists(atPath: agentPlistURL.path)
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Result<Status, Error> {
        do {
            if enabled {
                try enable()
            } else {
                try disable()
            }
            return .success(currentStatus())
        } catch {
            return .failure(error)
        }
    }

    static func openSystemSettings() {
        systemService.openSystemSettings()
    }

    /// DerivedData 重建后保持 LaunchAgent 可执行路径新鲜。
    /// 绝不替 ad-hoc Debug 构建自动重装 agent——那会孵化出多个卡死的副本。
    static func refreshIfNeeded(preferenceEnabled: Bool) {
        guard preferenceEnabled else { return }
        systemService.refresh()
        if systemService.status == .on { return }
        // 只刷新已存在的 LaunchAgent 路径，不在后台新建。
        guard launchAgentInstalled else { return }
        _ = try? installLaunchAgent()
    }

    private static func enable() throws {
        // 系统登录项能用就走 MacKit；只有 .notFound（典型是未签名 Debug）才允许 LaunchAgent。
        let smStatus = SMAppService.mainApp.status
        if smStatus != .notFound {
            switch systemService.setEnabled(true) {
            case .success:
                removeLaunchAgentQuietly()
                return
            case .failure(let error):
                throw error
            }
        }
        try installLaunchAgent()
    }

    private static func disable() throws {
        let smStatus = SMAppService.mainApp.status
        if smStatus == .enabled || smStatus == .requiresApproval {
            _ = systemService.setEnabled(false)
        }
        try removeLaunchAgent()
    }

    private static func installLaunchAgent() throws {
        guard let exe = Bundle.main.executableURL?.path else {
            throw LaunchError.missingExecutable
        }

        let plist: [String: Any] = [
            "Label": agentLabel,
            "ProgramArguments": [exe],
            "RunAtLoad": true,
            "LimitLoadToSessionType": "Aqua"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let dir = agentPlistURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: agentPlistURL, options: .atomic)

        let uid = getuid()
        let domain = "gui/\(uid)"
        _ = runLaunchctl(["bootout", domain, agentPlistURL.path])
        let boot = runLaunchctl(["bootstrap", domain, agentPlistURL.path])
        if boot != 0 {
            _ = runLaunchctl(["load", "-w", agentPlistURL.path])
        }
    }

    private static func removeLaunchAgent() throws {
        let uid = getuid()
        let domain = "gui/\(uid)"
        if FileManager.default.fileExists(atPath: agentPlistURL.path) {
            _ = runLaunchctl(["bootout", domain, agentPlistURL.path])
            _ = runLaunchctl(["unload", "-w", agentPlistURL.path])
            try? FileManager.default.removeItem(at: agentPlistURL)
        }
    }

    private static func removeLaunchAgentQuietly() {
        try? removeLaunchAgent()
    }

    @discardableResult
    private static func runLaunchctl(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }

    enum LaunchError: LocalizedError {
        case missingExecutable

        var errorDescription: String? {
            String(localized: "error.launch.missingExecutable")
        }
    }
}
