import Foundation

/// Reads Codex's local session event stream. It never reads credentials or
/// calls an undocumented service; the CLI writes these rate-limit updates as
/// part of normal operation.
public final class CodexSessionUsageSource: @unchecked Sendable {
    private let sessionsDirectory: URL
    private let fileManager: FileManager

    public init(sessionsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".codex/sessions", isDirectory: true),
                fileManager: FileManager = .default) {
        self.sessionsDirectory = sessionsDirectory
        self.fileManager = fileManager
    }

    /// Newest 12 .jsonl files by mtime, first one that yields rate limits wins.
    public func latestLanes(now: Date) -> [LaneUsage]? {
        guard let files = try? recentFiles(limit: 12) else { return nil }
        for url in files {
            guard let text = try? String(contentsOf: url, encoding: .utf8),
                  let snap = CodexRateLimitParser.snapshot(fromJSONLines: text, now: now) else { continue }
            return snap.lanes
        }
        return nil
    }

    private func recentFiles(limit: Int) throws -> [URL] {
        guard fileManager.fileExists(atPath: sessionsDirectory.path) else {
            throw CocoaError(.fileNoSuchFile)
        }

        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey]
        guard let enumerator = fileManager.enumerator(at: sessionsDirectory,
                                                      includingPropertiesForKeys: Array(keys)) else {
            throw CocoaError(.fileReadUnknown)
        }
        var files: [(url: URL, modified: Date)] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl",
                  let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true else { continue }
            files.append((url, values.contentModificationDate ?? .distantPast))
        }
        return files.sorted(by: { $0.modified > $1.modified }).prefix(limit).map(\.url)
    }
}
