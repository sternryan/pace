import Foundation
import PaceCore

/// Reads Codex's local session event stream. It never reads credentials or
/// calls an undocumented service; the CLI writes these rate-limit updates as
/// part of normal operation.
final class CodexSessionUsageSource: UsageSource, @unchecked Sendable {
    private let sessionsDirectory: URL
    private let fileManager: FileManager

    init(sessionsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/sessions", isDirectory: true),
         fileManager: FileManager = .default) {
        self.sessionsDirectory = sessionsDirectory
        self.fileManager = fileManager
    }

    func fetch() async -> Result<UsageSnapshot, FetchStatus>? {
        await Task.detached { [self] in loadSnapshot() }.value
    }

    private func loadSnapshot() -> Result<UsageSnapshot, FetchStatus>? {
        guard fileManager.fileExists(atPath: sessionsDirectory.path) else {
            return .failure(.parseError("Codex session directory was not found"))
        }

        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey]
        guard let enumerator = fileManager.enumerator(at: sessionsDirectory,
                                                      includingPropertiesForKeys: Array(keys)) else {
            return .failure(.transient("couldn't read the Codex session directory"))
        }
        var files: [(url: URL, modified: Date)] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl",
                  let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true else { continue }
            files.append((url, values.contentModificationDate ?? .distantPast))
        }

        for file in files.sorted(by: { $0.modified > $1.modified }).prefix(12) {
            guard let data = try? Data(contentsOf: file.url),
                  let text = String(data: data, encoding: .utf8) else { continue }
            if let snapshot = CodexRateLimitParser.snapshot(fromJSONLines: text) {
                return .success(snapshot)
            }
        }
        return .failure(.parseError("no rate-limit event has been recorded yet"))
    }
}
