import SwiftUI

@main
struct IsletApp: App {
    var body: some Scene {
        MenuBarExtra("Islet", systemImage: "capsule.fill") {
            Button("Quit Islet") {
                NSApp.terminate(nil)
            }
        }
    }
}
