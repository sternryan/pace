// Local shim (NOT vendored from openusage) — see Sources/PaceCore/Vendor/VENDORED.md.
import Foundation
import os

/// Local no-op stand-in for upstream's `AppLog`/`LogTag` (`Sources/OpenUsage/Support/AppLog.swift`).
/// The real implementation is a full logging facility (user-configurable level floor, redaction,
/// a grep-friendly file sink at `~/Library/Logs/OpenUsage/OpenUsage.log`, `LogFile`, `LogLevelSetting`)
/// wired into OpenUsage's app lifecycle — telemetry/app-shell infra out of scope for PaceCore per
/// CLAUDE.md ("PaceCore stays free of AppKit and WebKit" / no app-lifecycle wiring). Stubbed here to
/// a bare `os.Logger` pass-through so the vendored scanners/pricing code keep their call sites
/// unchanged; PaceCore's own logging (if any) is a `Pace`-target concern.
enum LogTag: Sendable {
    case cache
    case http
    case config
    case keychain
    case refresh

    static func plugin(_ id: String) -> String { "plugin:\(id)" }

    var rawValue: String {
        switch self {
        case .cache: "cache"
        case .http: "http"
        case .config: "config"
        case .keychain: "keychain"
        case .refresh: "refresh"
        }
    }
}

enum AppLog {
    private static let loggerLock = NSLock()
    private nonisolated(unsafe) static var loggers: [String: Logger] = [:]

    static func error(_ tag: String, _ message: @autoclosure () -> String) { emit(.error, tag, message()) }
    static func warn(_ tag: String, _ message: @autoclosure () -> String) { emit(.default, tag, message()) }
    static func info(_ tag: String, _ message: @autoclosure () -> String) { emit(.info, tag, message()) }
    static func debug(_ tag: String, _ message: @autoclosure () -> String) { emit(.debug, tag, message()) }

    static func error(_ tag: LogTag, _ message: @autoclosure () -> String) { error(tag.rawValue, message()) }
    static func warn(_ tag: LogTag, _ message: @autoclosure () -> String) { warn(tag.rawValue, message()) }
    static func info(_ tag: LogTag, _ message: @autoclosure () -> String) { info(tag.rawValue, message()) }
    static func debug(_ tag: LogTag, _ message: @autoclosure () -> String) { debug(tag.rawValue, message()) }

    private static func emit(_ level: OSLogType, _ tag: String, _ message: String) {
        logger(for: tag).log(level: level, "[\(tag, privacy: .public)] \(message, privacy: .public)")
    }

    private static func logger(for tag: String) -> Logger {
        loggerLock.lock()
        defer { loggerLock.unlock() }
        if let existing = loggers[tag] { return existing }
        let logger = Logger(subsystem: "Pace", category: tag)
        loggers[tag] = logger
        return logger
    }
}

/// Local stand-in for upstream's `LogRedaction.bodyPreview` (`Sources/OpenUsage/Support/LogRedaction.swift`),
/// which truncates and scrubs a response body for a debug log line. PaceCore's stub never logs the
/// body at all, since there is no configurable debug-level sink to gate it here.
enum LogRedaction {
    static func bodyPreview(_ body: String) -> String { "<body omitted>" }
    static func redactURL(_ url: String) -> String { "<url omitted>" }
}

/// Local stand-in for upstream's `Bundle.openUsageResources` (`Sources/OpenUsage/Support/ResourceBundle.swift`),
/// which locates OpenUsage's copied resources (bundled pricing JSON snapshots, provider SVGs) across a
/// packaged `.app`'s `Contents/Resources`, a companion CLI helper, and `swift run`/`swift test` build
/// paths via `ContainingAppBundle` — app-packaging infra out of scope for PaceCore. PaceCore never
/// bundles those JSON snapshots and always constructs pricing via `ModelPricing.empty` /
/// `PricingSupplement`'s in-memory initializer, so `ModelPricingStore.bundledResourceData` (the only
/// caller) is expected to always miss and return nil here.
extension Bundle {
    static let openUsageResources: Bundle = .main
}
