import KeyboardShortcuts
import SwiftUI

struct SettingsActions {
    var exportJSON: () -> Void
    var importJSON: () -> Void
    var revealDatabase: () -> Void
    var copyDatabasePath: () -> Void
    var resetWindowPosition: () -> Void
}

@MainActor
@Observable
final class SettingsStatusModel {
    var message: String?
    var databaseVersion: String = "—"
    var databaseSize: String = "—"
    var databasePath: String = "—"
}

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    let hotKey: HotKeyManager
    let status: SettingsStatusModel
    let updateService: SoftwareUpdateService
    let actions: SettingsActions

    var body: some View {
        Form {
            Section("外观") {
                Picker("外观模式", selection: appearanceBinding) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 8) {
                    Text("窗口透明度")
                    Slider(value: opacityBinding, in: 0.55...1.0, step: 0.01)
                    Text("\(Int((settings.opacity * 100).rounded()))%")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
            }

            Section("窗口行为") {
                Toggle("始终置顶", isOn: alwaysOnTopBinding)
                Toggle("跨桌面空间显示", isOn: acrossSpacesBinding)
                Toggle("菜单栏显示今日完成数", isOn: menuBarCountBinding)
                Toggle("开机自动启动", isOn: launchAtLoginBinding)
                if let error = settings.launchAtLoginError {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
                Text("登录启动由 macOS 登录项管理：\(StartupService.statusDescription)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Button("重置窗口位置") {
                    actions.resetWindowPosition()
                }
            }

            Section("快捷键") {
                KeyboardShortcuts.Recorder("全局唤出窗口", name: .togglePanel, onChange: { _ in
                    hotKey.checkConflicts()
                })
                KeyboardShortcuts.Recorder("快速添加（可选）", name: .quickAdd, onChange: { _ in
                    hotKey.checkConflicts()
                })
                Text(hotKey.conflictMessage ?? "当前：\(hotKey.shortcutDescription) · 使用 Carbon 热键，无需辅助功能权限")
                    .font(.system(size: 11))
                    .foregroundStyle(hotKey.conflictMessage == nil ? Color.secondary : Color.red)
                Button("检查快捷键冲突") {
                    hotKey.checkConflicts()
                }
            }

            Section("数据") {
                LabeledContent("数据库版本", value: status.databaseVersion)
                LabeledContent("数据库大小", value: status.databaseSize)
                LabeledContent("存储位置") {
                    Text(status.databasePath)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                HStack(spacing: 8) {
                    Button("导出 JSON…") { actions.exportJSON() }
                    Button("导入备份…") { actions.importJSON() }
                    Button("在 Finder 中显示") { actions.revealDatabase() }
                    Button("复制路径") { actions.copyDatabasePath() }
                }
                Text("历史记录永久保留，不会被自动清理。导入采用按 id 合并，不会清空现有数据。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if let message = status.message {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Section("更新") {
                LabeledContent("当前版本", value: AppInfo.appVersion)
                Toggle("启动时自动检查更新", isOn: autoCheckBinding)
                HStack(spacing: 8) {
                    Button("检查更新") {
                        Task { await updateService.check(userInitiated: true) }
                    }
                    .disabled(updateService.state.isBusy)
                    Text(updateService.statusText)
                        .font(.system(size: 11))
                        .foregroundStyle(updateColor)
                }
                updateDetail
            }

            Section("关于") {
                LabeledContent("版本", value: AppInfo.appVersion)
                LabeledContent("快捷键", value: "⌘N 新建 · ⌘F 搜索历史 · ⌘Z 撤销 · ⌘, 设置")
                Text("TinyTodo · \(AppInfo.tagline)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("MIT License · 完全本地运行，不联网、不上传任何数据")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 600)
        .onAppear {
            hotKey.checkConflicts()
            settings.refreshLaunchAtLoginStatus()
        }
    }

    // MARK: - Bindings

    private var appearanceBinding: Binding<AppearanceMode> {
        Binding(get: { settings.appearance }, set: { settings.appearance = $0 })
    }

    private var opacityBinding: Binding<Double> {
        Binding(get: { settings.opacity }, set: { settings.opacity = $0 })
    }

    private var alwaysOnTopBinding: Binding<Bool> {
        Binding(get: { settings.alwaysOnTop }, set: { settings.alwaysOnTop = $0 })
    }

    private var acrossSpacesBinding: Binding<Bool> {
        Binding(get: { settings.acrossSpaces }, set: { settings.acrossSpaces = $0 })
    }

    private var menuBarCountBinding: Binding<Bool> {
        Binding(get: { settings.showMenuBarCount }, set: { settings.showMenuBarCount = $0 })
    }

    private var autoCheckBinding: Binding<Bool> {
        Binding(get: { settings.autoCheckForUpdates }, set: { settings.autoCheckForUpdates = $0 })
    }

    private var updateColor: Color {
        switch updateService.state {
        case .failed: return .red
        case .available: return .accentColor
        default: return .secondary
        }
    }

    @ViewBuilder
    private var updateDetail: some View {
        switch updateService.state {
        case let .available(candidate):
            VStack(alignment: .leading, spacing: 6) {
                Text("发现新版本 \(candidate.version)（当前 \(AppInfo.shortVersion)）")
                    .font(.system(size: 12, weight: .semibold))
                if !candidate.notes.isEmpty {
                    Text(candidate.notes)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(8)
                        .textSelection(.enabled)
                }
                HStack(spacing: 10) {
                    Button("下载并安装") {
                        Task { await updateService.downloadAndInstall() }
                    }
                    Link("发布说明", destination: candidate.htmlURL)
                    Text(ByteCountFormatter.string(fromByteCount: candidate.size, countStyle: .file))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                if !UpdateInstaller.canSelfUpdate(bundlePath: Bundle.main.bundleURL.path) {
                    Text("当前副本不在 /Applications，无法自动替换；请手动下载安装。")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
            }
            .padding(.top, 2)
        case .downloading:
            ProgressView().controlSize(.small)
        case .verifying, .installing:
            ProgressView().controlSize(.small)
        default:
            EmptyView()
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { settings.launchAtLogin },
            set: { settings.setLaunchAtLogin($0) }
        )
    }
}
