import SwiftUI

@main
struct PaceApp: App {
    @State private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuView(state: state)
        } label: {
            Image(nsImage: IconRenderer.image(for: state.pinned, stale: state.isStale))
        }
        .menuBarExtraStyle(.window)

        Settings {
            PreferencesView(state: state)
        }
    }
}
