import SwiftUI
import UniformTypeIdentifiers

struct IOSSettingsView: View {
    @Environment(IOSAppModel.self) private var model
    @State private var pickingFolder = false

    var body: some View {
        Form {
            Section("同步") {
                LabeledContent("当前存储", value: model.storageDescription)
                Button(model.isUsingICloud ? "更换 iCloud 文件夹…" : "使用 iCloud Drive…") {
                    pickingFolder = true
                }
                if model.isUsingICloud {
                    Button("改回本机存储", role: .destructive) { model.useLocalStorage() }
                }
                Text("在 iCloud Drive 里选择与 Mac 相同的那一个 TinyTodo 文件夹，两台设备就会读写同一个数据库。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("关于") {
                LabeledContent("版本", value: Bundle.main.shortVersionString)
                Text("TinyTodo · 记录不应该成为负担")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let error = model.errorMessage {
                Section("错误") {
                    Text(error).foregroundStyle(.red).font(.footnote)
                }
            }
        }
        .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { result in
            switch result {
            case let .success(url):
                model.useICloudFolder(url)
            case let .failure(error):
                model.setError(error.localizedDescription)
            }
        }
    }
}

extension Bundle {
    var shortVersionString: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
}
