import SwiftUI
import ServiceManagement

struct PreferencesView: View {
    @Bindable var appState: AppState
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchAtLoginError: String?

    var body: some View {
        Form {
            Stepper(value: $appState.refreshInterval, in: 60...1800, step: 60) {
                Text("Refresh every \(Int(appState.refreshInterval / 60)) min")
            }
            .onChange(of: appState.refreshInterval) { _, _ in appState.startTimer() }

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
                        // instead of showing a state that isn't true
                        // (review finding, cross-model: "the toggle can lie").
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                        launchAtLoginError = error.localizedDescription
                    }
                }
            if let launchAtLoginError {
                Text(launchAtLoginError).font(.caption).foregroundStyle(.red)
            }

            if appState.mode == .browser {
                Button("Sign out of claude.ai") { appState.signOut() }
            }
        }
        .padding(20)
        .frame(width: 320)
        .onAppear {
            // Re-sync with the real OS status every time Preferences opens —
            // the @State init-time snapshot goes stale if registration
            // status changes outside this view.
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
