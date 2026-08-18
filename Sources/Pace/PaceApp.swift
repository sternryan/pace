import SwiftUI

@main
struct PaceApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuView(appState: appState)
        } label: {
            Image(nsImage: IconRenderer.render(readings: appState.paceReadings, status: appState.status))
        }
        .menuBarExtraStyle(.window)

        Settings {
            PreferencesView(appState: appState)
        }
    }
}
