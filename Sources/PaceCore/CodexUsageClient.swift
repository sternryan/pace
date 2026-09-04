import Foundation

public struct CodexUsageClient: Sendable {
    static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    static let refreshURL = URL(string: "https://auth.openai.com/oauth/token")!
    static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    let session: URLSession

    public init(session: URLSession = {
        let c = URLSessionConfiguration.ephemeral; c.timeoutIntervalForRequest = 10; return URLSession(configuration: c)
    }()) { self.session = session }

    public enum Failure: Error, Equatable { case unauthorized, http(Int), transport(String) }

    public func fetchUsage(auth: CodexAuth) async -> Result<Data, Failure> {
        var req = URLRequest(url: Self.usageURL)
        req.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Pace", forHTTPHeaderField: "User-Agent")
        if let a = auth.accountID { req.setValue(a, forHTTPHeaderField: "ChatGPT-Account-Id") }
        do {
            let (data, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 || code == 403 { return .failure(.unauthorized) }
            guard (200..<300).contains(code) else { return .failure(.http(code)) }
            return .success(data)
        } catch { return .failure(.transport(error.localizedDescription)) }
    }

    /// POST form grant_type=refresh_token. Returns the new auth (refresh token may rotate).
    public func refresh(auth: CodexAuth, now: Date) async -> CodexAuth? {
        guard let rt = auth.refreshToken else { return nil }
        var req = URLRequest(url: Self.refreshURL); req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = "grant_type=refresh_token&client_id=\(Self.clientID)&refresh_token=\(rt)".data(using: .utf8)
        guard let (data, resp) = try? await session.data(for: req),
              (200..<300).contains((resp as? HTTPURLResponse)?.statusCode ?? 0),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = obj["access_token"] as? String else { return nil }
        return CodexAuth(accessToken: access, refreshToken: (obj["refresh_token"] as? String) ?? rt,
                         accountID: auth.accountID, lastRefresh: now)
    }
}
