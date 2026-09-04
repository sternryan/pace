import XCTest
@testable import PaceCore

final class CodexAuthStoreTests: XCTestCase {
    func write(_ json: String) throws -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try json.write(to: u, atomically: true, encoding: .utf8); return u
    }
    func testReadsTokensBlock() throws {
        let u = try write(#"{"auth_mode":"chatgpt","tokens":{"access_token":"A","refresh_token":"R","account_id":"acct"},"last_refresh":"2026-09-01T00:00:00Z"}"#)
        let auth = CodexAuthStore(fileURL: u).load()!
        XCTAssertEqual(auth.accessToken, "A"); XCTAssertEqual(auth.refreshToken, "R"); XCTAssertEqual(auth.accountID, "acct")
    }
    func testMissingFileIsNil() {
        XCTAssertNil(CodexAuthStore(fileURL: URL(fileURLWithPath: "/nonexistent/auth.json")).load())
    }
    func testNeedsRefreshWhenJWTExpiresWithinFiveMinutes() throws {
        // header.payload.sig with payload {"exp": now+60}
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let payload = Data(#"{"exp":1800000060}"#.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
        let auth = CodexAuth(accessToken: "h.\(payload).s", refreshToken: "R", accountID: nil, lastRefresh: nil)
        XCTAssertTrue(CodexAuthStore.needsRefresh(auth, now: now))
        let far = Data(#"{"exp":1800009999}"#.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
        XCTAssertFalse(CodexAuthStore.needsRefresh(CodexAuth(accessToken: "h.\(far).s", refreshToken: "R", accountID: nil, lastRefresh: nil), now: now))
    }
}
