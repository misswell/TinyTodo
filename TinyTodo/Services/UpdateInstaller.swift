import AppKit
import Foundation

struct StagedUpdate: Sendable {
    let stagedApp: URL
    let destinationApp: URL
    let logURL: URL
}

protocol UpdateInstalling: Sendable {
    func verifyAndStage(candidate: UpdateCandidate, dmgURL: URL) throws -> StagedUpdate
    func launchHelper(for staged: StagedUpdate) throws
}

struct UpdateInstaller: UpdateInstalling {
    static let helperScriptName = "update-helper"
    static let helperScriptExtension = "sh"

    /// Only an app living in /Applications may replace itself. A copy in Downloads or a mounted
    /// DMG says so instead of "successfully" overwriting a different bundle.
    static func canSelfUpdate(bundlePath: String) -> Bool {
        let path = URL(fileURLWithPath: bundlePath).standardizedFileURL.path
        return ["/Applications/TinyTodo.app", "/System/Volumes/Data/Applications/TinyTodo.app"].contains(path)
    }

    static var logURL: URL {
        let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library", isDirectory: true)
        return logs.appendingPathComponent("Logs/TinyTodo/update.log")
    }

    func verifyAndStage(candidate: UpdateCandidate, dmgURL: URL) throws -> StagedUpdate {
        let destination = Bundle.main.bundleURL
        guard Self.canSelfUpdate(bundlePath: destination.path) else {
            throw UpdateError.installationUnavailable
        }

        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("TinyTodoUpdate-\(UUID().uuidString)", isDirectory: true)
        let mountPoint = work.appendingPathComponent("mnt", isDirectory: true)
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        let attach = try Command.run("/usr/bin/hdiutil", [
            "attach", "-readonly", "-nobrowse", "-mountpoint", mountPoint.path, dmgURL.path
        ])
        guard attach.status == 0 else { throw UpdateError.commandFailed("hdiutil attach") }
        defer { _ = try? Command.run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-quiet"]) }

        let sourceApp = mountPoint.appendingPathComponent("TinyTodo.app", isDirectory: true)
        guard FileManager.default.fileExists(atPath: sourceApp.path) else {
            throw UpdateError.invalidApplication
        }
        try verifyBundle(at: sourceApp, expectedVersion: candidate.version)

        let cacheRoot = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TinyTodo/Update", isDirectory: true)
        let targetDir = cacheRoot.appendingPathComponent(candidate.version.description, isDirectory: true)
        try? FileManager.default.removeItem(at: targetDir)
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        let stagedApp = targetDir.appendingPathComponent("TinyTodo.app", isDirectory: true)

        let copy = try Command.run("/usr/bin/ditto", [sourceApp.path, stagedApp.path])
        guard copy.status == 0 else { throw UpdateError.commandFailed("ditto") }
        try verifyBundle(at: stagedApp, expectedVersion: candidate.version)

        return StagedUpdate(stagedApp: stagedApp, destinationApp: destination, logURL: Self.logURL)
    }

    /// Verification mirrors the other local apps: identity, version, signature, team, the same
    /// designated requirement (so TCC grants survive) and Gatekeeper acceptance.
    func verifyBundle(at app: URL, expectedVersion: SemanticVersion) throws {
        let infoURL = app.appendingPathComponent("Contents/Info.plist")
        guard let data = FileManager.default.contents(atPath: infoURL.path),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let bundleID = plist["CFBundleIdentifier"] as? String,
              let executable = plist["CFBundleExecutable"] as? String,
              bundleID == TinyTodoIdentity.bundleIdentifier,
              executable == TinyTodoIdentity.executableName else {
            throw UpdateError.invalidApplication
        }
        // Reported separately: a release whose asset carries the previous version's binary is a
        // publishing mistake, and "not a valid app" would send the user hunting the wrong thing.
        guard let versionString = plist["CFBundleShortVersionString"] as? String,
              let version = SemanticVersion(versionString) else {
            throw UpdateError.invalidApplication
        }
        guard version == expectedVersion else {
            throw UpdateError.versionMismatch
        }

        let verify = try Command.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", "--verbose=0", app.path])
        guard verify.status == 0 else { throw UpdateError.invalidSignature }

        let details = try Command.run("/usr/bin/codesign", ["-dvvv", app.path])
        guard details.output.contains("TeamIdentifier=\(TinyTodoIdentity.developerTeamIdentifier)") else {
            throw UpdateError.wrongDeveloperTeam
        }

        let currentRequirement = try Command.run("/usr/bin/codesign", ["-d", "-r-", Bundle.main.bundleURL.path]).output
        let candidateRequirement = try Command.run("/usr/bin/codesign", ["-d", "-r-", app.path]).output
        guard Self.normalizeRequirement(currentRequirement) == Self.normalizeRequirement(candidateRequirement) else {
            throw UpdateError.invalidSignature
        }

        let gatekeeper = try Command.run("/usr/sbin/spctl", ["--assess", "--type", "execute", "--verbose=0", app.path])
        guard gatekeeper.status == 0 else { throw UpdateError.gatekeeperRejected }
    }

    func launchHelper(for staged: StagedUpdate) throws {
        guard let script = Bundle.main.url(forResource: Self.helperScriptName, withExtension: Self.helperScriptExtension),
              FileManager.default.fileExists(atPath: script.path) else {
            throw UpdateError.helperMissing
        }
        try FileManager.default.createDirectory(
            at: staged.logURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            script.path,
            "\(ProcessInfo.processInfo.processIdentifier)",
            staged.stagedApp.path,
            staged.destinationApp.path,
            staged.logURL.path
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw UpdateError.commandFailed("update-helper")
        }
    }

    static func normalizeRequirement(_ output: String) -> String {
        output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("Executable=") }
            .joined(separator: " ")
            .replacingOccurrences(of: "designated => ", with: "")
    }
}

enum Command {
    static func run(_ executable: String, _ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            throw UpdateError.commandFailed((executable as NSString).lastPathComponent)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
