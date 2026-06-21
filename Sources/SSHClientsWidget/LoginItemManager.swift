import Foundation
import ServiceManagement

final class LoginItemManager: ObservableObject {
    static let shared = LoginItemManager()

    @Published var isEnabled: Bool

    private init() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            isEnabled = SMAppService.mainApp.status == .enabled
        } catch {
            isEnabled = SMAppService.mainApp.status == .enabled
            NSLog("Shorkut: failed to update login item: \(error)")
        }
    }

    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}
