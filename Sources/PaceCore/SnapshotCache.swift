import Foundation

/// Persists the last successful UsageSnapshot so a relaunch (or a fetch
/// failure) renders real last-known numbers with an age label instead of a
/// blank icon. Contains percentages and timestamps only — never credentials.
public struct SnapshotCache {
    private let fileURL: URL

    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("last-usage.json")
    }

    public static func defaultDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pace", isDirectory: true)
    }

    public func load() -> UsageSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(UsageSnapshot.self, from: data)
    }

    public func save(_ snapshot: UsageSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
