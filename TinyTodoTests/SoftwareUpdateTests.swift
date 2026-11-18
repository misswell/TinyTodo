import Foundation
import XCTest
@testable import TinyTodo

final class SemanticVersionTests: XCTestCase {
    func testParsesPrefixedAndShortVersions() {
        XCTAssertEqual(SemanticVersion("v1.1.0")?.description, "1.1.0")
        XCTAssertEqual(SemanticVersion("1.1")?.description, "1.1")
        XCTAssertEqual(SemanticVersion("2")?.description, "2")
        XCTAssertNil(SemanticVersion("v1.1.0-beta"))
        XCTAssertNil(SemanticVersion("abc"))
    }

    func testComparison() {
        XCTAssertTrue(SemanticVersion("1.10.0")! > SemanticVersion("1.9.9")!)
        XCTAssertEqual(SemanticVersion("1.1")!, SemanticVersion("1.1.0")!)
        XCTAssertTrue(SemanticVersion("1.0.1")! > SemanticVersion("1.0.0")!)
        XCTAssertFalse(SemanticVersion("1.0.0")! > SemanticVersion("1.0")!)
    }
}

final class ReleaseDecodingTests: XCTestCase {
    private func json(tag: String = "v1.2.0", draft: Bool = false, prerelease: Bool = false, digest: String? = "sha256:" + String(repeating: "a", count: 64), assetName: String? = nil) -> Data {
        let name = assetName ?? "TinyTodo-1.2.0.dmg"
        let digestField = digest.map { #", "digest": "\#($0)""# } ?? ""
        return Data("""
        {
          "tag_name": "\(tag)",
          "body": "notes",
          "html_url": "https://github.com/misswell/TinyTodo/releases/tag/\(tag)",
          "draft": \(draft),
          "prerelease": \(prerelease),
          "assets": [
            {"name": "\(name)", "browser_download_url": "https://github.com/misswell/TinyTodo/releases/download/\(tag)/\(name)", "size": 1234\(digestField)}
          ]
        }
        """.utf8)
    }

    func testDecodesRelease() throws {
        let release = try ReleaseInfo.decodeGitHubResponse(json())
        XCTAssertEqual(release.tagName, "v1.2.0")
        XCTAssertEqual(release.assets.count, 1)
        XCTAssertEqual(release.assets[0].size, 1234)
        XCTAssertTrue(release.assets[0].digest?.hasPrefix("sha256:") == true)
    }

    func testCandidateRequiresExpectedNameAndDigest() throws {
        let release = try ReleaseInfo.decodeGitHubResponse(json())
        let candidate = try UpdateCandidate.make(from: release)
        XCTAssertEqual(candidate.version.description, "1.2.0")
        XCTAssertEqual(candidate.assetName, "TinyTodo-1.2.0.dmg")
        XCTAssertEqual(candidate.digest, String(repeating: "a", count: 64))
    }

    func testCandidateRejectsMissingDigest() throws {
        let release = try ReleaseInfo.decodeGitHubResponse(json(digest: nil))
        XCTAssertThrowsError(try UpdateCandidate.make(from: release)) { error in
            XCTAssertEqual(error as? UpdateError, .missingVerifiedArchive)
        }
    }

    func testCandidateRejectsWrongAssetName() throws {
        let release = try ReleaseInfo.decodeGitHubResponse(json(assetName: "TinyTodo-1.2.0.zip"))
        XCTAssertThrowsError(try UpdateCandidate.make(from: release)) { error in
            XCTAssertEqual(error as? UpdateError, .missingVerifiedArchive)
        }
    }

    func testCandidateRejectsDraftAndPrerelease() throws {
        let draft = try ReleaseInfo.decodeGitHubResponse(json(draft: true))
        XCTAssertThrowsError(try UpdateCandidate.make(from: draft))
        let pre = try ReleaseInfo.decodeGitHubResponse(json(prerelease: true))
        XCTAssertThrowsError(try UpdateCandidate.make(from: pre))
    }
}

private struct StubProvider: ReleaseProviding {
    let result: Result<ReleaseInfo, Error>
    func latestRelease() async throws -> ReleaseInfo { try result.get() }
}

@MainActor
final class SoftwareUpdateServiceTests: XCTestCase {
    private func release(_ tag: String) throws -> ReleaseInfo {
        try ReleaseInfo.decodeGitHubResponse(Data("""
        {
          "tag_name": "\(tag)",
          "body": "notes",
          "html_url": "https://github.com/misswell/TinyTodo/releases/tag/\(tag)",
          "draft": false,
          "prerelease": false,
          "assets": [
            {"name": "TinyTodo-\(tag.hasPrefix("v") ? String(tag.dropFirst()) : tag).dmg",
             "browser_download_url": "https://github.com/misswell/TinyTodo/releases/download/\(tag)/TinyTodo.dmg",
             "size": 100, "digest": "sha256:\(String(repeating: "b", count: 64))"}
          ]
        }
        """.utf8))
    }

    func testNewerReleaseBecomesAvailable() async throws {
        let service = SoftwareUpdateService(provider: StubProvider(result: .success(try release("v9.9.9"))))
        await service.check(userInitiated: true)
        guard case let .available(candidate) = service.state else {
            return XCTFail("expected available, got \(service.state)")
        }
        XCTAssertEqual(candidate.version.description, "9.9.9")
    }

    func testSameVersionIsUpToDate() async throws {
        let current = AppInfo.shortVersion
        let service = SoftwareUpdateService(provider: StubProvider(result: .success(try release("v\(current)"))))
        await service.check(userInitiated: true)
        XCTAssertEqual(service.state, .upToDate)
    }

    func testFailureIsVisibleWhenUserInitiatedAndSilentWhenAutomatic() async {
        let service = SoftwareUpdateService(provider: StubProvider(result: .failure(UpdateError.invalidResponse)))
        await service.checkAutomatically()
        XCTAssertEqual(service.state, .idle)

        await service.check(userInitiated: true)
        if case .failed = service.state {} else { XCTFail("expected failed, got \(service.state)") }
    }

    func testAutomaticCheckRunsOnlyOnce() async throws {
        final class CountingProvider: ReleaseProviding, @unchecked Sendable {
            var count = 0
            let release: ReleaseInfo
            init(release: ReleaseInfo) { self.release = release }
            func latestRelease() async throws -> ReleaseInfo {
                count += 1
                return release
            }
        }
        let provider = CountingProvider(release: try release("v9.9.9"))
        let service = SoftwareUpdateService(provider: provider)
        await service.checkAutomatically()
        await service.checkAutomatically()
        XCTAssertEqual(provider.count, 1)
    }
}

final class UpdateDigestTests: XCTestCase {
    func testDigestVerification() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("digest-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("tiny todo".utf8).write(to: url)

        let sha = try UpdateDigest.sha256(fileURL: url)
        XCTAssertEqual(sha.count, 64)
        XCTAssertNoThrow(try UpdateDigest.verify(fileURL: url, expectedSHA256: sha.uppercased()))
        XCTAssertThrowsError(try UpdateDigest.verify(fileURL: url, expectedSHA256: String(repeating: "0", count: 64))) { error in
            XCTAssertEqual(error as? UpdateError, .digestMismatch)
        }
    }
}

final class UpdateInstallerTests: XCTestCase {
    func testOnlyApplicationsCopiesMaySelfUpdate() {
        XCTAssertTrue(UpdateInstaller.canSelfUpdate(bundlePath: "/Applications/TinyTodo.app"))
        XCTAssertTrue(UpdateInstaller.canSelfUpdate(bundlePath: "/System/Volumes/Data/Applications/TinyTodo.app"))
        XCTAssertFalse(UpdateInstaller.canSelfUpdate(bundlePath: "/Users/me/Downloads/TinyTodo.app"))
        XCTAssertFalse(UpdateInstaller.canSelfUpdate(bundlePath: "/Volumes/TinyTodo/TinyTodo.app"))
    }

    func testRequirementNormalization() {
        let a = "Executable=/Applications/TinyTodo.app/Contents/MacOS/TinyTodo\ndesignated => identifier \"app.tinytodo.TinyTodo\" and anchor apple generic"
        let b = "Executable=/tmp/TinyTodo.app/Contents/MacOS/TinyTodo\ndesignated => identifier \"app.tinytodo.TinyTodo\" and anchor apple generic"
        XCTAssertEqual(UpdateInstaller.normalizeRequirement(a), UpdateInstaller.normalizeRequirement(b))
    }

    func testHelperScriptIsBundled() {
        XCTAssertNotNil(Bundle.main.url(forResource: UpdateInstaller.helperScriptName, withExtension: UpdateInstaller.helperScriptExtension))
    }
}

final class UpdateBundleVerificationTests: XCTestCase {
    private func makeBundle(version: String, bundleID: String = "app.tinytodo.TinyTodo", executable: String = "TinyTodo") throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TinyTodoBundle-\(UUID().uuidString)", isDirectory: true)
        let contents = root.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": bundleID,
            "CFBundleExecutable": executable,
            "CFBundleShortVersionString": version
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return root
    }

    func testVersionDriftIsReportedAsVersionMismatch() throws {
        let app = try makeBundle(version: "1.2.1")
        defer { try? FileManager.default.removeItem(at: app) }
        let installer = UpdateInstaller()
        XCTAssertThrowsError(try installer.verifyBundle(at: app, expectedVersion: SemanticVersion("1.2.2")!)) { error in
            XCTAssertEqual(error as? UpdateError, .versionMismatch)
        }
    }

    func testWrongBundleIdentifierIsInvalidApplication() throws {
        let app = try makeBundle(version: "1.2.2", bundleID: "com.example.other")
        defer { try? FileManager.default.removeItem(at: app) }
        let installer = UpdateInstaller()
        XCTAssertThrowsError(try installer.verifyBundle(at: app, expectedVersion: SemanticVersion("1.2.2")!)) { error in
            XCTAssertEqual(error as? UpdateError, .invalidApplication)
        }
    }

    func testMissingBundleIsInvalidApplication() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("nope-\(UUID().uuidString).app")
        XCTAssertThrowsError(try UpdateInstaller().verifyBundle(at: missing, expectedVersion: SemanticVersion("1.2.2")!)) { error in
            XCTAssertEqual(error as? UpdateError, .invalidApplication)
        }
    }
}
