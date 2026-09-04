import Foundation
import Network

public final class LoopbackServer: @unchecked Sendable {
    public static let defaultPort: UInt16 = 6737
    private let port: UInt16
    private let report: @Sendable () -> PaceReport?
    private let refresh: @Sendable () async -> PaceReport?
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "pace.loopback")
    private var active = 0
    private let maxConnections = 8

    public init(port: UInt16 = LoopbackServer.defaultPort, report: @escaping @Sendable () -> PaceReport?,
                refresh: @escaping @Sendable () async -> PaceReport?) {
        self.port = port; self.report = report; self.refresh = refresh
    }

    public func start() throws {
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port) ?? .any)
        let l = try NWListener(using: params)
        l.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
        l.start(queue: queue)
        listener = l
    }

    public func stop() { listener?.cancel(); listener = nil }

    public func boundPort() async throws -> UInt16 {
        for _ in 0..<50 {
            if let p = listener?.port?.rawValue, p != 0 { return p }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw URLError(.cannotConnectToHost)
    }

    private func handle(_ conn: NWConnection) {
        queue.async { [weak self] in
            guard let self else { conn.cancel(); return }
            guard self.active < self.maxConnections else { conn.cancel(); return }
            self.active += 1
            conn.start(queue: self.queue)
            self.receiveRequestLine(conn, buffer: Data())
        }
    }

    /// Accumulates into `buffer` across as many `receive` calls as it takes to see a
    /// complete request line (`\r\n`). A client can deliver the request split across
    /// multiple TCP segments, so a single `receive` is not guaranteed to contain it.
    private func receiveRequestLine(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, error in
            guard let self else { return }
            guard error == nil, let data, !data.isEmpty else {
                conn.cancel()
                self.queue.async { self.active -= 1 }
                return
            }
            var buffer = buffer
            buffer.append(data)
            let head = String(decoding: buffer, as: UTF8.self)
            guard let range = head.range(of: "\r\n") else {
                guard buffer.count <= 8192 else {
                    self.send(conn, status: 400, body: Data("{\"error\":\"request line too long\"}".utf8))
                    return
                }
                self.receiveRequestLine(conn, buffer: buffer)
                return
            }
            let line = String(head[head.startIndex..<range.lowerBound])
            let parts = line.split(separator: " ")
            let method = parts.count > 0 ? String(parts[0]) : ""
            let path = parts.count > 1 ? String(parts[1]) : ""
            Task {
                let response: (Int, Data)
                switch (method, path) {
                case ("GET", "/v1/report"):  response = self.encode(self.report())
                case ("POST", "/v1/refresh"): response = self.encode(await self.refresh())
                default: response = (404, Data("{\"error\":\"not found\"}".utf8))
                }
                self.send(conn, status: response.0, body: response.1)
            }
        }
    }

    private func encode(_ r: PaceReport?) -> (Int, Data) {
        guard let r else { return (503, Data("{\"error\":\"no report yet\"}".utf8)) }
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (200, (try? enc.encode(r)) ?? Data("{}".utf8))
    }

    private func send(_ conn: NWConnection, status: Int, body: Data) {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 400: reason = "Bad Request"
        case 404: reason = "Not Found"
        default: reason = "Service Unavailable"
        }
        let head = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        conn.send(content: Data(head.utf8) + body, completion: .contentProcessed { [weak self] _ in
            conn.cancel()
            self?.queue.async { self?.active -= 1 }
        })
    }
}
