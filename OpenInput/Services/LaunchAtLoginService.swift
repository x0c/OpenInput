import AppKit
import Foundation
import ServiceManagement

/// Login-item registration that works for both signed installs (SMAppService)
/// and ad-hoc / DerivedData builds (LaunchAgent fallback).
enum LaunchAtLoginService {
    private static let agentLabel = "com.x0c.openinput.launchagent"
    private static var agentPlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(agentLabel).plist")
    }

    enum Status: Equatable {
        case on
        case off
        case needsApproval

        var isEffectivelyOn: Bool {
            self == .on
        }
    }

    static func currentStatus() -> Status {
        switch SMAppService.mainApp.status {
        case .enabled:
            return .on
        case .requiresApproval:
            return .needsApproval
        case .notFound, .notRegistered:
            return launchAgentInstalled ? .on : .off
        @unknown default:
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

    /// Keep LaunchAgent executable path fresh after DerivedData rebuilds.
    /// Never auto-reinstall agents for ad-hoc Debug builds — that can spawn many hung copies.
    static func refreshIfNeeded(preferenceEnabled: Bool) {
        guard preferenceEnabled else { return }
        if SMAppService.mainApp.status == .enabled { return }
        // Only refresh an existing LaunchAgent path; do not create new ones in the background.
        guard launchAgentInstalled else { return }
        _ = try? installLaunchAgent()
    }

    private static func enable() throws {
        // Prefer ServiceManagement. Avoid LaunchAgent fallback for unsigned Debug builds —
        // they hang easily and KeepAlive-less agents still leave zombie Dock tiles.
        let smStatus = SMAppService.mainApp.status
        if smStatus != .notFound {
            try SMAppService.mainApp.register()
            removeLaunchAgentQuietly()
            return
        }
        // Debug / ad-hoc: still allow LaunchAgent but only when user explicitly toggles on.
        try installLaunchAgent()
    }

    private static func disable() throws {
        if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval {
            try? SMAppService.mainApp.unregister()
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
            "找不到应用可执行文件"
        }
    }
}
