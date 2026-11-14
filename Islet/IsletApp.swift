import SwiftUI

enum SettingsKey {
    static let expandOnHover = "expandOnHover"
    static let showVolume = "showVolume"
    static let showCharging = "showCharging"
    static let showLockScreenPlayer = "showLockScreenPlayer"
}

@main
struct IsletApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        UserDefaults.standard.register(defaults: [
            SettingsKey.expandOnHover: true,
            SettingsKey.showVolume: true,
            SettingsKey.showCharging: true,
            SettingsKey.showLockScreenPlayer: true
        ])
    }

    var body: some Scene {
        MenuBarExtra("Islet", systemImage: "capsule.fill") {
            SettingsMenu()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: IslandModel?
    private var islandPanelController: IslandPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = IslandModel()
        islandPanelController = IslandPanelController(model: model)
        model.start()
        self.model = model
    }
}

struct SettingsMenu: View {
    var body: some View {
        Button("Quit Islet") {
            NSApp.terminate(nil)
        }
    }
}
