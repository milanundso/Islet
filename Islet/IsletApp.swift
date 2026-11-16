import SwiftUI
import ServiceManagement

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
    private var lockScreenController: LockScreenController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = IslandModel()
        islandPanelController = IslandPanelController(model: model)
        lockScreenController = LockScreenController(nowPlaying: model.nowPlaying)
        model.start()
        self.model = model
    }
}

struct SettingsMenu: View {
    @AppStorage(SettingsKey.expandOnHover) private var expandOnHover = true
    @AppStorage(SettingsKey.showVolume) private var showVolume = true
    @AppStorage(SettingsKey.showCharging) private var showCharging = true
    @AppStorage(SettingsKey.showLockScreenPlayer) private var showLockScreenPlayer = true
    @State private var launchesAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle("Expand on hover", isOn: $expandOnHover)
        Toggle("Volume indicator", isOn: $showVolume)
        Toggle("Charging indicator", isOn: $showCharging)
        Toggle("Lock screen player", isOn: $showLockScreenPlayer)
        Divider()
        Toggle("Launch at login", isOn: Binding(
            get: { launchesAtLogin },
            set: { shouldLaunch in
                if shouldLaunch {
                    try? SMAppService.mainApp.register()
                } else {
                    try? SMAppService.mainApp.unregister()
                }
                launchesAtLogin = SMAppService.mainApp.status == .enabled
            }
        ))
        Divider()
        Button("Quit Islet") {
            NSApp.terminate(nil)
        }
    }
}
