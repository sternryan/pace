import SwiftUI
import PaceCore

struct MenuView: View {
    @Bindable var appState: AppState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Claude Usage")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 6)

            ForEach(appState.paceReadings, id: \.lane.kind) { reading in
                LaneRow(reading: reading)
                Divider()
            }

            if let extra = appState.latestSnapshot?.extraUsage, extra.isEnabled, extra.dollarsUsed > 0 {
                HStack {
                    Text("Extra usage").font(.system(size: 12.5)).foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "$%.2f", extra.dollarsUsed)).font(.system(size: 12.5, weight: .semibold))
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                Divider()
            }

            statusRow

            Divider()
            MenuActionRow(title: "Refresh now", hint: appState.lastSuccessLabel) { appState.refreshNow() }
            MenuActionRow(title: "Open claude.ai usage", hint: nil) { appState.openClaudeUsagePage() }
            MenuActionRow(title: "Preferences…", hint: nil) { openSettings() }
            MenuActionRow(title: "Quit", hint: nil) { NSApplication.shared.terminate(nil) }
        }
        .frame(width: 300)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var statusRow: some View {
        if appState.isShowingCachedData, appState.status == .ok {
            Text("Showing cached data\(appState.latestSnapshot.map { " · fetched \(PaceFormatter.ageLabel(since: $0.fetchedAt, now: Date()))" } ?? "")")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 16).padding(.vertical, 6)
        }
        switch appState.status {
        case .needsLogin:
            Button("Sign in to claude.ai") { appState.presentLogin() }
                .buttonStyle(.plain)
                .padding(.horizontal, 16).padding(.vertical, 6)
        case .tokenExpired:
            Text("Claude Code login expired — open Claude Code and run /login. Showing last known values.")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 16).padding(.vertical, 6)
        case .transient(let detail):
            Text("Couldn't reach the usage API (\(detail)). Showing last known values.")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 16).padding(.vertical, 6)
        case .navigationFailed(let detail):
            Text("\(detail). Showing last known values — open claude.ai directly to check.")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 16).padding(.vertical, 6)
        case .parseError(let detail):
            Text("Couldn't refresh usage (\(detail)). Showing last known values.")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 16).padding(.vertical, 6)
        case .ok:
            EmptyView()
        }
    }
}

private struct LaneRow: View {
    let reading: PaceReading

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(reading.lane.effectiveDisplayName).font(.system(size: 12.5)).foregroundStyle(.secondary)
                Spacer()
                Text("\(reading.lane.percentUsed)%")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(reading.isAlarmed ? Color.red : Color.primary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.gray.opacity(0.3))
                    // Semantic colors, not hardcoded near-white: the popover
                    // background follows the system appearance, so white-on-white
                    // made the fill and the pace tick invisible in light mode.
                    RoundedRectangle(cornerRadius: 2)
                        .fill(reading.isAlarmed ? Color.red : Color.primary)
                        .frame(width: geo.size.width * CGFloat(reading.lane.percentUsed) / 100)
                    if let percentElapsed = reading.percentElapsed {
                        Rectangle().fill(Color(nsColor: .windowBackgroundColor).opacity(0.9))
                            .frame(width: 2)
                            .offset(x: geo.size.width * CGFloat(percentElapsed) / 100)
                    }
                }
            }
            .frame(height: 5)

            HStack {
                Text(PaceFormatter.resetLabel(for: reading.lane, now: Date()))
                Spacer()
                if let percentElapsed = reading.percentElapsed {
                    Text("\(percentElapsed)% of window elapsed")
                }
            }
            .font(.system(size: 11)).foregroundStyle(.secondary)

            if let capDate = reading.projectedCapDate, let capBeforeReset = reading.capBeforeReset,
               capBeforeReset || reading.isAlarmed {
                Text("Projected to hit cap \(PaceFormatter.projectionLabel(capDate: capDate, resetDate: reading.lane.resetDate, capBeforeReset: capBeforeReset))")
                    .font(.system(size: 11))
                    .foregroundStyle(capBeforeReset ? Color.red : Color.secondary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }
}

private struct MenuActionRow: View {
    let title: String
    let hint: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 12.5))
                Spacer()
                if let hint { Text(hint).font(.system(size: 11)).foregroundStyle(.secondary) }
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
// Mock hot-lane data for visual verification — replaces hardcoding a
// LaneUsage into AppState.init and reverting it afterward, which risked
// shipping a forgotten test edit.
#Preview("Hot lane") {
    let now = Date()
    let hotLane = LaneUsage(kind: .session, percentUsed: 70, resetDate: now.addingTimeInterval(3600), windowLength: 5 * 3600)
    let coolLane = LaneUsage(kind: .allModelsWeek, percentUsed: 20, resetDate: now.addingTimeInterval(4 * 24 * 3600), windowLength: 7 * 24 * 3600)
    let readings = [hotLane, coolLane].map { PaceCalculator.reading(for: $0, now: now) }
    return VStack {
        ForEach(readings, id: \.lane.kind) { reading in
            Image(nsImage: IconRenderer.render(readings: [reading], status: .ok))
        }
    }
    .padding()
}
#endif
