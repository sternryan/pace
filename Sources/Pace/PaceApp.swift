import SwiftUI
import PaceCore

@main
struct PaceApp: App {
    // One AppState per provider: separate sources, separate caches, separate
    // refresh timers. They are deliberately NOT merged into one verdict --
    // pace v3 did that on 2026-09-05 and was reverted the same day because two
    // glanceable icons read faster than one collapsed headline
    // (docs/NOTES-2026-09-05-v3-revert.md).
    @State private var claude = AppState(provider: .claude)
    @State private var codex = AppState(provider: .codex)

    var body: some Scene {
        MenuBarExtra {
            MenuView(appState: claude)
        } label: {
            Image(nsImage: IconRenderer.render(readings: claude.paceReadings, status: claude.status))
        }
        .menuBarExtraStyle(.window)

        MenuBarExtra {
            MenuView(appState: codex)
        } label: {
            Image(nsImage: IconRenderer.render(readings: codex.paceReadings, status: codex.status))
        }
        .menuBarExtraStyle(.window)

        Settings {
            PreferencesView(appState: claude)
        }
    }
}
