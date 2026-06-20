import XCTest

/// Decoder tests against a real `/api/oauth/usage` response.
final class UsageDecodingTests: XCTestCase {

    /// Abbreviated real response (values preserved).
    private let json = """
    {
      "five_hour": { "utilization": 0.0, "resets_at": "2026-06-21T03:20:00.913060+00:00" },
      "seven_day": { "utilization": 14.0, "resets_at": "2026-06-21T03:00:00.913087+00:00" },
      "seven_day_opus": null,
      "seven_day_sonnet": { "utilization": 0.0, "resets_at": null },
      "spend": {
        "used": { "amount_minor": 0, "currency": "EUR", "exponent": 2 },
        "limit": { "amount_minor": 1000, "currency": "EUR", "exponent": 2 },
        "enabled": false
      }
    }
    """

    private func decode() throws -> UsageResponse {
        try JSONDecoder().decode(UsageResponse.self, from: Data(json.utf8))
    }

    func testUtilizationIsPercent() throws {
        let r = try decode()
        XCTAssertEqual(r.fiveHour?.percentUsed, 0)
        XCTAssertEqual(r.sevenDay?.percentUsed, 14)
        XCTAssertEqual(r.sevenDaySonnet?.percentUsed, 0)
    }

    func testOpusAbsentIsNil() throws {
        XCTAssertNil(try decode().sevenDayOpus)
    }

    func testMicrosecondDateParses() throws {
        XCTAssertNotNil(try decode().fiveHour?.resetsAt)
        XCTAssertNil(try decode().sevenDaySonnet?.resetsAt)
    }

    func testSpendMoneyConversion() throws {
        let spend = try decode().spend
        XCTAssertEqual(spend?.used?.value, 0)
        XCTAssertEqual(spend?.limit?.value, 10)   // 1000 minor / 10^2
        XCTAssertEqual(spend?.limit?.currency, "EUR")
    }

    func testSnapshotMapping() throws {
        let snapshot = UsageSnapshot.from(try decode(), fetchedAt: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(snapshot.sessionPercent, 0)
        XCTAssertEqual(snapshot.weeklyPercent, 14)
        XCTAssertNil(snapshot.opusPercent)
        XCTAssertEqual(snapshot.sonnetPercent, 0)
        XCTAssertEqual(snapshot.spendText, "€0.00 / €10.00")
        XCTAssertEqual(snapshot.maxPercent, 14)
    }

    func testFractionUtilizationClamped() throws {
        // A 0...1 style value should still be treated as a percent (clamped 0...100).
        let r = try JSONDecoder().decode(UsageResponse.self,
            from: Data(#"{"five_hour":{"utilization":150}}"#.utf8))
        XCTAssertEqual(r.fiveHour?.percentUsed, 100)
    }
}
