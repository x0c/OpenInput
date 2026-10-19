#!/usr/bin/swift
import AppKit
import Foundation
import Darwin

let bundleID = "com.x0c.openinput"
let executable = URL(fileURLWithPath: "/Applications/OpenInput.app/Contents/MacOS/OpenInput").standardizedFileURL

func matchingApplications() -> [NSRunningApplication] {
    NSWorkspace.shared.runningApplications.filter {
        $0.bundleIdentifier == bundleID && $0.executableURL?.standardizedFileURL == executable && !$0.isTerminated
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

switch CommandLine.arguments.dropFirst().first {
case "stop":
    for app in matchingApplications() {
        guard let current = NSRunningApplication(processIdentifier: app.processIdentifier),
              current.bundleIdentifier == bundleID,
              current.executableURL?.standardizedFileURL == executable,
              current.launchDate == app.launchDate else { continue }
        guard Darwin.kill(current.processIdentifier, SIGTERM) == 0 else {
            fail("Could not signal the verified installed app; no files replaced.")
        }
    }
    let deadline = Date().addingTimeInterval(8)
    while !matchingApplications().isEmpty, Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    guard matchingApplications().isEmpty else { fail("The installed app is still running; no files replaced.") }
    print("Stopped all matching installed app instances.")
case "verify":
    let apps = matchingApplications()
    guard apps.count == 1, let app = apps.first else { fail("Expected exactly one installed app instance; found \(apps.count).") }
    print("Installed app running: PID \(app.processIdentifier), bundle \(bundleID)")
default:
    fail("Usage: manage-installed-app.swift stop|verify")
}
