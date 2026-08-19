import XCTest
@testable import PaceCore

final class ClaudeCodeCredentialTests: XCTestCase {
    func testParsesNestedClaudeAiOauthShape() throws {
        // The shape Claude Code writes: {"claudeAiOauth": {...}} with
        // expiresAt in epoch MILLISECONDS.
        let json = Data(#"{"claudeAiOauth":{"accessToken":"tok-a","expiresAt":1787204000000,"refreshToken":"r"}}"#.utf8)
        let credential = try XCTUnwrap(ClaudeCodeCredential.parse(itemData: json))
        XCTAssertEqual(credential.accessToken, "tok-a")
        XCTAssertEqual(credential.expiresAt, Date(timeIntervalSince1970: 1_787_204_000))
    }

    func testParsesFlatShapeAndMissingExpiry() throws {
        let flat = try XCTUnwrap(ClaudeCodeCredential.parse(itemData: Data(#"{"accessToken":"tok-b"}"#.utf8)))
        XCTAssertEqual(flat.accessToken, "tok-b")
        XCTAssertNil(flat.expiresAt)
    }

    func testGarbageParsesToNil() {
        XCTAssertNil(ClaudeCodeCredential.parse(itemData: Data("nope".utf8)))
        XCTAssertNil(ClaudeCodeCredential.parse(itemData: Data(#"{"claudeAiOauth":{}}"#.utf8)))
    }

    func testSelectFreshestPicksLatestNonExpired() {
        // The trap found live on 2026-08-19: multiple Keychain items share
        // the service name; a single-match read returned the STALE one and
        // reported "revoked" forever, right after a successful login.
        let now = Date(timeIntervalSince1970: 1_787_200_000)
        let stale = ClaudeCodeCredential(accessToken: "old", expiresAt: now.addingTimeInterval(-86400))
        let fresh = ClaudeCodeCredential(accessToken: "new", expiresAt: now.addingTimeInterval(8 * 3600))
        let fresher = ClaudeCodeCredential(accessToken: "newest", expiresAt: now.addingTimeInterval(9 * 3600))
        XCTAssertEqual(ClaudeCodeCredential.selectFreshest(from: [stale, fresher, fresh], now: now)?.accessToken, "newest")
    }

    func testSelectFreshestAllExpiredReturnsNil() {
        let now = Date(timeIntervalSince1970: 1_787_200_000)
        let a = ClaudeCodeCredential(accessToken: "a", expiresAt: now.addingTimeInterval(-1))
        XCTAssertNil(ClaudeCodeCredential.selectFreshest(from: [a], now: now))
        XCTAssertNil(ClaudeCodeCredential.selectFreshest(from: [], now: now))
    }

    func testMissingExpiryTreatedAsUsableButLeastPreferred() {
        let now = Date(timeIntervalSince1970: 1_787_200_000)
        let unknown = ClaudeCodeCredential(accessToken: "unknown", expiresAt: nil)
        let dated = ClaudeCodeCredential(accessToken: "dated", expiresAt: now.addingTimeInterval(3600))
        XCTAssertEqual(ClaudeCodeCredential.selectFreshest(from: [unknown, dated], now: now)?.accessToken, "dated")
        XCTAssertEqual(ClaudeCodeCredential.selectFreshest(from: [unknown], now: now)?.accessToken, "unknown")
    }
}
