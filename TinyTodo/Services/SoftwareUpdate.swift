import AppKit
import CryptoKit
import Foundation
import Observation

enum TinyTodoIdentity {
    static let name = "TinyTodo"
    static let bundleIdentifier = "app.tinytodo.TinyTodo"
    static let executableName = "TinyTodo"
    static let githubRepository = "misswell/TinyTodo"
    static let developerTeamIdentifier = "U8U443D7ZL"

    static func dmgName(for version: SemanticVersion) -> String {
        "TinyTodo-\(version.description).dmg"
    }
}

struct ReleaseAssetInfo: Equatable, Sendable {
    let name: String
    let url: URL
    let digest: String?
    let size: Int64
}

struct ReleaseInfo: Equatable, Sendable {
    let tagName: String
    let body: String
    let htmlURL: URL
    let draft: Bool
    let prerelease: Bool
    let assets: [ReleaseAssetInfo]

    static func decodeGitHubResponse(_ data: Data) throws -> ReleaseInfo {
        let response: GitHubReleaseResponse
        do {
            response = try JSONDecoder().decode(GitHubReleaseResponse.self, from: data)
        } catch {
            throw UpdateError.invalidResponse
        }
        return ReleaseInfo(
            tagName: response.tagName,
            body: response.body ?? "",
            htmlURL: response.htmlURL,
            draft: response.draft,
            prerelease: response.prerelease,
            assets: response.assets.map {
                ReleaseAssetInfo(name: $0.name, url: $0.url, digest: $0.digest, size: $0.size)
            }
        )
    }
}

private struct GitHubReleaseResponse: Decodable {
    struct Asset: Decodable {
        let name: String
        let url: URL
        let digest: String?
        let size: Int64

        enum CodingKeys: String, CodingKey {
            case name
            case url = "browser_download_url"
            case digest
            case size
        }
    }

    let tagName: String
    let body: String?
    let htmlURL: URL
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case body
        case htmlURL = "html_url"
        case draft
        case prerelease
        case assets
    }
}

enum UpdateError: LocalizedError, Equatable {
    case invalidResponse
    case httpStatus(Int)
    case invalidRelease
    case missingVerifiedArchive
    case digestMismatch
    case invalidApplication
    case versionMismatch
    case invalidSignature
    case wrongDeveloperTeam
    case gatekeeperRejected
    case installationUnavailable
    case helperMissing
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "GitHub Release 数据无法解析"
        case let .httpStatus(code):
            if code == 403 || code == 429 { return "GitHub API 请求受限（HTTP \(code)），请稍后重试" }
            return "GitHub 返回异常响应（HTTP \(code)）"
        case .invalidRelease: return "最新 Release 不是可用的正式版本"
        case .missingVerifiedArchive: return "Release 中没有带 SHA-256 的 DMG 安装包"
        case .digestMismatch: return "下载文件的 SHA-256 与 GitHub 记录不一致"
        case .invalidApplication: return "安装包不是有效的 TinyTodo.app"
        case .versionMismatch: return "安装包版本与 Release 标签不一致"
        case .invalidSignature: return "安装包签名校验失败"
        case .wrongDeveloperTeam: return "安装包不是 Developer ID（U8U443D7ZL）签名"
        case .gatekeeperRejected: return "安装包未通过 Gatekeeper/公证校验"
        case .installationUnavailable: return "当前应用不在 /Applications，无法自动更新，请手动下载"
        case .helperMissing: return "应用内缺少更新组件，请手动下载安装"
        case let .commandFailed(command): return "系统命令失败：\(command)"
        }
    }
}

protocol ReleaseProviding: Sendable {
    func latestRelease() async throws -> ReleaseInfo
}

struct GitHubReleaseProvider: ReleaseProviding {
    var repository: String = TinyTodoIdentity.githubRepository
    var session: URLSession = .shared

    func latestRelease() async throws -> ReleaseInfo {
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else {
            throw UpdateError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("TinyTodo/\(AppInfo.shortVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UpdateError.invalidResponse }
        guard http.statusCode == 200 else { throw UpdateError.httpStatus(http.statusCode) }
        return try ReleaseInfo.decodeGitHubResponse(data)
    }
}

struct UpdateCandidate: Equatable, Identifiable, Sendable {
    var id: String { version.description }
    let version: SemanticVersion
    let tag: String
    let notes: String
    let assetName: String
    let downloadURL: URL
    let digest: String
    let size: Int64
    let htmlURL: URL

    /// The DMG must be published under the exact expected name and carry GitHub's sha256 digest.
    static func make(from release: ReleaseInfo) throws -> UpdateCandidate {
        guard !release.draft, !release.prerelease,
              let version = SemanticVersion(release.tagName) else {
            throw UpdateError.invalidRelease
        }
        let expectedName = TinyTodoIdentity.dmgName(for: version)
        guard let asset = release.assets.first(where: { $0.name == expectedName }),
              asset.url.scheme == "https",
              let digest = asset.digest,
              digest.lowercased().hasPrefix("sha256:") else {
            throw UpdateError.missingVerifiedArchive
        }
        let sha = String(digest.dropFirst("sha256:".count)).lowercased()
        guard sha.count == 64, sha.allSatisfy(\.isHexDigit) else {
            throw UpdateError.missingVerifiedArchive
        }
        return UpdateCandidate(
            version: version,
            tag: release.tagName,
            notes: release.body,
            assetName: asset.name,
            downloadURL: asset.url,
            digest: sha,
            size: asset.size,
            htmlURL: release.htmlURL
        )
    }
}

@MainActor
@Observable
final class SoftwareUpdateService {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(UpdateCandidate)
        case downloading
        case verifying
        case installing
        case failed(String)

        var isBusy: Bool {
            switch self {
            case .checking, .downloading, .verifying, .installing: return true
            default: return false
            }
        }
    }

    private let provider: ReleaseProviding
    private let installer: UpdateInstalling
    private let session: URLSession
    private var hasAutoChecked = false

    private(set) var state: State = .idle
    private(set) var lastChecked: Date?

    init(
        provider: ReleaseProviding = GitHubReleaseProvider(),
        installer: UpdateInstalling = UpdateInstaller(),
        session: URLSession = .shared
    ) {
        self.provider = provider
        self.installer = installer
        self.session = session
    }

    var currentVersion: SemanticVersion? {
        SemanticVersion(AppInfo.shortVersion)
    }

    var statusText: String {
        switch state {
        case .idle: return lastChecked.map { "上次检查：\(Self.timeString($0))" } ?? "尚未检查"
        case .checking: return "正在检查更新…"
        case .upToDate: return "已是最新版本"
        case let .available(candidate): return "发现新版本 \(candidate.version)"
        case .downloading: return "正在下载安装包…"
        case .verifying: return "正在校验签名与公证…"
        case .installing: return "正在安装并重启…"
        case let .failed(message): return message
        }
    }

    func checkAutomatically() async {
        guard !hasAutoChecked else { return }
        hasAutoChecked = true
        await check(userInitiated: false)
    }

    func check(userInitiated: Bool) async {
        guard !state.isBusy else { return }
        state = .checking
        do {
            let release = try await provider.latestRelease()
            let candidate = try UpdateCandidate.make(from: release)
            lastChecked = Date()
            if let current = currentVersion, candidate.version > current {
                state = .available(candidate)
            } else {
                state = .upToDate
            }
        } catch {
            lastChecked = Date()
            if userInitiated {
                state = .failed(Self.message(for: error))
            } else {
                // Automatic checks stay silent; the pane shows the last state when opened.
                state = .idle
            }
        }
    }

    func downloadAndInstall() async {
        guard case let .available(candidate) = state else { return }
        guard let downloadURL = candidate.downloadURL as URL? else { return }
        state = .downloading
        do {
            let (tempURL, response) = try await session.download(from: downloadURL)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw UpdateError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
            }
            state = .verifying
            let staged = try await Task.detached(priority: .userInitiated) { [installer] in
                try UpdateDigest.verify(fileURL: tempURL, expectedSHA256: candidate.digest)
                return try installer.verifyAndStage(candidate: candidate, dmgURL: tempURL)
            }.value
            state = .installing
            try await Task.detached(priority: .userInitiated) { [installer] in
                try installer.launchHelper(for: staged)
            }.value
            // The helper waits for this process to exit, swaps the bundle and relaunches.
            NSApp.terminate(nil)
        } catch {
            state = .failed(Self.message(for: error))
        }
    }

    static func message(for error: Error) -> String {
        if let updateError = error as? UpdateError {
            return updateError.errorDescription ?? "更新失败"
        }
        return "更新失败：\(error.localizedDescription)"
    }

    private static func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

enum UpdateDigest {
    static func sha256(fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func verify(fileURL: URL, expectedSHA256: String) throws {
        let actual = try sha256(fileURL: fileURL)
        guard actual.caseInsensitiveCompare(expectedSHA256) == .orderedSame else {
            throw UpdateError.digestMismatch
        }
    }
}
