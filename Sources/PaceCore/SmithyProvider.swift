import Foundation

public struct SmithyProvider: Provider {
    public let id: ProviderID = .smithy
    public static let defaultModelsURL = URL(string: "http://100.85.83.97:8085/v1/models")!
    public static let defaultLeaseURL = URL(string: "http://100.122.29.52:8001/lease")!
    let modelsURL: URL, leaseURL: URL, session: URLSession

    public init(schedulerModelsURL: URL = SmithyProvider.defaultModelsURL, leaseURL: URL = SmithyProvider.defaultLeaseURL,
                session: URLSession = { let c = URLSessionConfiguration.ephemeral; c.timeoutIntervalForRequest = 5; return URLSession(configuration: c) }()) {
        modelsURL = schedulerModelsURL; self.leaseURL = leaseURL; self.session = session
    }

    public func fetch(now: Date) async -> ProviderSnapshot {
        let session = self.session
        let modelsURL = self.modelsURL
        let leaseURL = self.leaseURL
        async let m = Self.get(modelsURL, session: session)
        async let l = Self.get(leaseURL, session: session)
        let (models, lease) = await (m, l)
        let state = Self.map(models: models, lease: lease)
        var err: ProviderError? = nil
        if models == nil { err = .unreachable("scheduler hearth:8085 not answering") }
        else if lease == nil { err = .unreachable("anvil lease server :8001 not answering") }
        return ProviderSnapshot(provider: .smithy, fetchedAt: now, source: .api, lanes: [], laneState: state, error: err)
    }

    /// serving  = local-heavy serving_now AND a candidate with status "ready" AND lease state "free"
    /// leasedAway = lane answers but lease is "held" or "wedged"
    /// unreachable = anything else (either GET failed, malformed, or lane not serving)
    public static func map(models: Data?, lease: Data?) -> LaneState {
        guard let models, let lease,
              let root = try? JSONSerialization.jsonObject(with: models) as? [String: Any],
              let data = root["data"] as? [[String: Any]],
              let heavy = data.first(where: { ($0["id"] as? String) == "local-heavy" }),
              let smithy = heavy["smithy"] as? [String: Any],
              (smithy["serving_now"] as? Bool) == true,
              let cands = smithy["candidates"] as? [[String: Any]],
              cands.contains(where: { ($0["status"] as? String) == "ready" }),
              let leaseObj = try? JSONSerialization.jsonObject(with: lease) as? [String: Any],
              let state = leaseObj["state"] as? String else { return .unreachable }
        switch state {
        case "free": return .serving
        case "held", "wedged": return .leasedAway
        default: return .unreachable
        }
    }

    private static func get(_ url: URL, session: URLSession) async -> Data? {
        guard let (data, resp) = try? await session.data(from: url),
              (200..<300).contains((resp as? HTTPURLResponse)?.statusCode ?? 0) else { return nil }
        return data
    }
}
