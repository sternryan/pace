import Foundation
import PaceCore

let args = CommandLine.arguments.dropFirst()
let wantJSON = args.contains("--json")
let wantRefresh = args.contains("--refresh")
if args.contains("--help") || args.contains("-h") {
    print("usage: pace [--json] [--refresh]\n  --json     print report.json verbatim\n  --refresh  force a fetch via the running app (127.0.0.1:6737), else fetch in-process")
    exit(0)
}

func fetchViaApp(path: String, method: String) async -> Data? {
    var req = URLRequest(url: URL(string: "http://127.0.0.1:\(LoopbackServer.defaultPort)\(path)")!)
    req.httpMethod = method; req.timeoutInterval = 30
    guard let (data, resp) = try? await URLSession.shared.data(for: req),
          (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
    return data
}

let semaphore = DispatchSemaphore(value: 0)
Task {
    let now = Date()
    var report: PaceReport? = nil
    if wantRefresh {
        if let data = await fetchViaApp(path: "/v1/refresh", method: "POST") {
            let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
            report = try? dec.decode(PaceReport.self, from: data)
        } else {
            report = await RefreshCoordinator.live().refresh()
        }
    } else {
        report = ReportStore(directory: ReportStore.defaultDirectory()).load()
        if report == nil { report = await RefreshCoordinator.live().refresh() }
    }
    guard let report else { FileHandle.standardError.write(Data("pace: no report available\n".utf8)); exit(2) }
    if wantJSON {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.sortedKeys, .prettyPrinted]
        print(String(decoding: try! enc.encode(report), as: UTF8.self))
    } else {
        print(ReportTextFormatter.render(report, now: now), terminator: "")
    }
    semaphore.signal()
}
semaphore.wait()
