import SwiftUI
import PaceCore

struct MenuView: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let r = state.report {
                if let h = r.headline {
                    Text(h.verdict).font(.headline)
                        .foregroundStyle(h.status == .ahead || h.status == .capped ? .red : .primary)
                }
                if let a = r.advice { Text(a).font(.subheadline) }
                Divider()
                ForEach([ProviderID.claude, .codex], id: \.self) { p in
                    let ws = r.windows.filter { $0.provider == p }
                    if !ws.isEmpty {
                        Text(p == .claude ? "Claude" : "Codex").font(.caption).foregroundStyle(.secondary)
                        ForEach(ws, id: \.kind) { w in WindowRow(w: w) }
                    }
                }
                Divider()
                HStack {
                    Text("smithy")
                    Spacer()
                    Text(laneLabel(r.laneState)).foregroundStyle(r.laneState == .serving ? .green : .orange)
                }
                if let b = r.burn, b.unparsedLines > 0 {
                    Text("\(b.unparsedLines) unparsed log lines").font(.caption).foregroundStyle(.orange)
                }
                ForEach(r.providers.filter { $0.error != nil }, id: \.provider) { p in
                    Text("\(p.provider.rawValue): \(p.error!)").font(.caption).foregroundStyle(.orange)
                }
            } else {
                Text("No data yet").foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Text(state.report.map { PaceFormatter.ageLabel(since: $0.generatedAt, now: Date()) } ?? "")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Refresh") { state.refreshNow() }.keyboardShortcut("r")
                SettingsLink { Text("Preferences") }
                Button("Quit") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
            }
        }
        .padding(12)
        .frame(width: 380)
    }

    func laneLabel(_ s: LaneState?) -> String {
        switch s {
        case .serving?: return "serving"
        case .leasedAway?: return "GPU leased"
        default: return "unreachable"
        }
    }
}

struct WindowRow: View {
    let w: WindowVerdict

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(w.kind.displayName)
                Spacer()
                Text("\(w.percentUsed)%").monospacedDigit()
                Text(w.source.rawValue).font(.caption2).foregroundStyle(.secondary)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Rectangle().fill(.quaternary)
                    Rectangle()
                        .fill(w.status == .ahead || w.status == .capped ? .red : .accentColor)
                        .frame(width: g.size.width * CGFloat(w.percentUsed) / 100)
                    if let e = w.percentElapsed {
                        Rectangle().fill(.primary).frame(width: 1).offset(x: g.size.width * CGFloat(e) / 100)
                    }
                }
            }
            .frame(height: 6)
            Text(w.verdict).font(.caption).foregroundStyle(.secondary)
        }
    }
}
