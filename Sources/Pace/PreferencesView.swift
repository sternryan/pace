import SwiftUI
import ServiceManagement
import PaceCore

struct PreferencesView: View {
    @Bindable var state: AppState

    var body: some View {
        Form {
            LaunchAtLoginToggle()
            Picker("Refresh every", selection: $state.refreshInterval) {
                Text("1 min").tag(TimeInterval(60))
                Text("2 min").tag(TimeInterval(120))
                Text("5 min").tag(TimeInterval(300))
            }
            Picker("Menubar pin", selection: $state.pinnedKind) {
                Text("Headline (auto)").tag(LaneKind?.none)
                ForEach(LaneKind.allCases, id: \.self) { k in
                    Text(k.displayName).tag(LaneKind?.some(k))
                }
            }
            Text("Overage percent is an unverified ÷100 of raw credits (see TODOS.md).")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 360)
    }
}

/// v2's SMAppService-backed launch-at-login toggle, unchanged in behavior —
/// extracted so PreferencesView can be replaced wholesale without losing it.
struct LaunchAtLoginToggle: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchAtLoginError: String?

    var body: some View {
        Group {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    do {
                        if newValue {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                        launchAtLoginError = nil
                    } catch {
                        // Registration failed — revert to the real status
                        // instead of showing a state that isn't true.
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                        launchAtLoginError = error.localizedDescription
                    }
                }
            if let launchAtLoginError {
                Text(launchAtLoginError).font(.caption).foregroundStyle(.red)
            }
        }
        .onAppear {
            // Re-sync with the real OS status every time Preferences opens —
            // the @State init-time snapshot goes stale if registration
            // status changes outside this view.
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
