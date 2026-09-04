import Foundation

public struct CodexAuth: Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let accountID: String?
    public let lastRefresh: Date?
    public init(accessToken: String, refreshToken: String?, accountID: String?, lastRefresh: Date?) {
        self.accessToken = accessToken; self.refreshToken = refreshToken; self.accountID = accountID; self.lastRefresh = lastRefresh
    }
}

public struct CodexAuthStore: Sendable {
    public let fileURL: URL
    public init(fileURL: URL = CodexAuthStore.defaultURL()) { self.fileURL = fileURL }

    public static func defaultURL() -> URL {
        if let home = ProcessInfo.processInfo.environment["CODEX_HOME"], !home.isEmpty {
            return URL(fileURLWithPath: home).appendingPathComponent("auth.json")
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/auth.json")
    }

    public func load() -> CodexAuth? {
        guard let data = try? Data(contentsOf: fileURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = obj["tokens"] as? [String: Any],
              let access = tokens["access_token"] as? String, !access.isEmpty else { return nil }
        let last = (obj["last_refresh"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
        return CodexAuth(accessToken: access, refreshToken: tokens["refresh_token"] as? String,
                         accountID: tokens["account_id"] as? String, lastRefresh: last)
    }

    /// JWT `exp` minus 5 min; if no exp, refresh when `last_refresh` is older than 8 days.
    public static func needsRefresh(_ auth: CodexAuth, now: Date) -> Bool {
        if let exp = jwtExpiry(auth.accessToken) { return now >= exp.addingTimeInterval(-300) }
        if let last = auth.lastRefresh { return now.timeIntervalSince(last) > 8 * 86400 }
        return false
    }

    static func jwtExpiry(_ token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var b64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = obj["exp"] as? Double else { return nil }
        return Date(timeIntervalSince1970: exp)
    }
}
