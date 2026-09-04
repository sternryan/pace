import Foundation

public struct ReportStore {
    public static let staleAfter: TimeInterval = 10 * 60
    public let fileURL: URL

    public init(directory: URL) { fileURL = directory.appendingPathComponent("report.json") }

    public static func defaultDirectory() -> URL { SnapshotCache.defaultDirectory() }

    public struct Loaded: Equatable { public let report: PaceReport; public let age: TimeInterval; public let isStale: Bool }

    public func save(_ report: PaceReport) throws {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try enc.encode(report)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tmp = fileURL.appendingPathExtension("tmp")
        try data.write(to: tmp, options: [.atomic])
        _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tmp)
    }

    public func load() -> PaceReport? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(PaceReport.self, from: data)
    }

    public func loadWithAge(now: Date) -> Loaded? {
        guard let r = load() else { return nil }
        let age = now.timeIntervalSince(r.generatedAt)
        return Loaded(report: r, age: age, isStale: age > Self.staleAfter)
    }
}
