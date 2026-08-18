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
        switch appState.status {
        case .needsLogin:
            Button("Sign in to claude.ai") { appState.presentLogin() }
                .buttonStyle(.plain)
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
                Text(reading.lane.kind.displayName).font(.system(size: 12.5)).foregroundStyle(.secondary)
                Spacer()
                Text("\(reading.lane.percentUsed)%")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(reading.isAheadOfPace ? Color.red : Color.primary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.gray.opacity(0.3))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(reading.isAheadOfPace ? Color.red : Color(white: 0.85))
                        .frame(width: geo.size.width * CGFloat(reading.lane.percentUsed) / 100)
                    if let percentElapsed = reading.percentElapsed {
                        Rectangle().fill(Color.white.opacity(0.9))
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

            if reading.isAheadOfPace, let capDate = reading.projectedCapDate {
                Text("Projected to hit cap \(PaceFormatter.projectionLabel(capDate: capDate, resetDate: reading.lane.resetDate))")
                    .font(.system(size: 11)).foregroundStyle(.red)
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
// LaneUsage into AppState.init and reverting it afterward (review finding:
// that approach risked shipping a forgotten test edit).
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
