import Foundation
import ServiceManagement
import os

enum StartupService {
    private static let logger = Logger(subsystem: AppInfo.subsystem, category: "startup")

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled: return "已启用"
        case .notRegistered: return "未启用"
        case .notFound: return "未找到（请将 App 放入 /Applications 后再启用）"
        case .requiresApproval: return "等待系统批准（系统设置 › 通用 › 登录项）"
        @unknown default: return "未知"
        }
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard SMAppService.mainApp.status != .enabled else { return }
            try SMAppService.mainApp.register()
            logger.info("login item registered")
        } else {
            guard SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval else { return }
            try SMAppService.mainApp.unregister()
            logger.info("login item unregistered")
        }
    }
}
