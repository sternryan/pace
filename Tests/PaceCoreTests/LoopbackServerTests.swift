import XCTest
import Network
@testable import PaceCore

final class LoopbackServerTests: XCTestCase {
    func testServesReportAnd404sElsewhere() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let report = PaceReport(generatedAt: now, headline: nil, advice: nil, windows: [], laneState: .serving, burn: nil, providers: [], stale: false)
        let server = LoopbackServer(port: 0, report: { report }, refresh: { report })   // port 0 = ephemeral, exposes .boundPort
        try server.start()
        defer { server.stop() }
        let port = try await server.boundPort()
        let (data, resp) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/v1/report")!)
        XCTAssertEqual((resp as? HTTPURLResponse)?.statusCode, 200)
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try dec.decode(PaceReport.self, from: data), report)
        let (_, r404) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/nope")!)
        XCTAssertEqual((r404 as? HTTPURLResponse)?.statusCode, 404)
    }

    /// The request line can arrive split across TCP reads. A naive single `receive` would
    /// parse the fragment "GET /v1/re" and 404 a request that is actually valid once
    /// the rest of the line lands.
    func testRequestLineSplitAcrossReadsStillResolves() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let report = PaceReport(generatedAt: now, headline: nil, advice: nil, windows: [], laneState: .serving, burn: nil, providers: [], stale: false)
        let server = LoopbackServer(port: 0, report: { report }, refresh: { report })
        try server.start()
        defer { server.stop() }
        let port = try await server.boundPort()

        let conn = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        let connQueue = DispatchQueue(label: "test.loopback.client")
        conn.start(queue: connQueue)
        try await waitReady(conn)

        try await sendData(conn, Data("GET /v1/re".utf8))
        try await Task.sleep(nanoseconds: 50_000_000)
        try await sendData(conn, Data("port HTTP/1.1\r\nHost: x\r\n\r\n".utf8))

        let responseData = try await receiveAll(conn)
        let responseText = String(decoding: responseData, as: UTF8.self)
        XCTAssertTrue(responseText.hasPrefix("HTTP/1.1 200"), "expected 200 OK, got: \(responseText.prefix(80))")
        conn.cancel()
    }

    /// A connection that is opened and cancelled before sending anything increments the
    /// `active` counter in `handle` but must decrement it on the closed-receive path too —
    /// otherwise a client that connects and drops (a port scanner, a browser prefetch,
    /// a client that gave up) permanently eats one of the `maxConnections` (8) slots.
    func testClosedConnectionDoesNotLeakConnectionCapacity() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let report = PaceReport(generatedAt: now, headline: nil, advice: nil, windows: [], laneState: .serving, burn: nil, providers: [], stale: false)
        let server = LoopbackServer(port: 0, report: { report }, refresh: { report })
        try server.start()
        defer { server.stop() }
        let port = try await server.boundPort()

        let conn = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        let connQueue = DispatchQueue(label: "test.loopback.client.drop")
        conn.start(queue: connQueue)
        try await waitReady(conn)
        conn.cancel()
        // Give the server a moment to observe the close and decrement its counter.
        try await Task.sleep(nanoseconds: 100_000_000)

        for _ in 0..<9 {
            let (_, resp) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/v1/report")!)
            XCTAssertEqual((resp as? HTTPURLResponse)?.statusCode, 200)
        }
    }

    // MARK: - NWConnection test helpers

    private func waitReady(_ conn: NWConnection) async throws {
        let resumed = Locked(false)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard resumed.trySet() else { return }
                    continuation.resume()
                case .failed(let error):
                    guard resumed.trySet() else { return }
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
        }
    }

    /// Guards a continuation against being resumed twice — `stateUpdateHandler` and
    /// `receive` completion handlers can each fire more than once after the first
    /// state we care about (e.g. `.ready` followed later by `.cancelled`/`.failed`).
    private final class Locked {
        private var value: Bool
        private let lock = NSLock()
        init(_ value: Bool) { self.value = value }
        func trySet() -> Bool {
            lock.lock(); defer { lock.unlock() }
            guard !value else { return false }
            value = true
            return true
        }
    }

    private func sendData(_ conn: NWConnection, _ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            conn.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
    }

    private func receiveAll(_ conn: NWConnection) async throws -> Data {
        var result = Data()
        while true {
            let (data, isComplete): (Data?, Bool) = try await withCheckedThrowingContinuation { continuation in
                conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: (data, isComplete)) }
                }
            }
            if let data { result.append(data) }
            if isComplete || data == nil { break }
            // The server sets Connection: close and cancels after sending; once we have a
            // full HTTP head + body marker we can stop waiting rather than blocking on EOF.
            if String(decoding: result, as: UTF8.self).contains("\r\n\r\n") { break }
        }
        return result
    }
}
