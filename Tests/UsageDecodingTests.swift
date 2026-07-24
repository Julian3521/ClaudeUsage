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
      "seven_day_fable": { "utilization": 27.0, "resets_at": "2026-06-21T03:00:00.913087+00:00" },
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

    private func model(_ key: String) throws -> ModelUsage? {
        try decode().models.first { $0.key == key }
    }

    func testUtilizationIsPercent() throws {
        let r = try decode()
        XCTAssertEqual(r.fiveHour?.percentUsed, 0)
        XCTAssertEqual(r.sevenDay?.percentUsed, 14)
        XCTAssertEqual(try model("sonnet")?.percent, 0)
    }

    func testOpusAbsentIsOmitted() throws {
        XCTAssertNil(try model("opus"))
    }

    /// Any `seven_day_<model>` window decodes, including ones we never hard-coded.
    func testUnknownModelWindowDecodes() throws {
        XCTAssertEqual(try model("fable")?.percent, 27)
        XCTAssertEqual(try model("fable")?.displayName, "Fable")
        let r = try JSONDecoder().decode(UsageResponse.self,
            from: Data(#"{"seven_day_brand_new":{"utilization":5}}"#.utf8))
        XCTAssertEqual(r.models.map(\.key), ["brand_new"])
        XCTAssertEqual(r.models.first?.displayName, "Brand New")
    }

    /// Known models sort by tier, unknown ones after them, alphabetically.
    func testModelOrder() throws {
        let r = try JSONDecoder().decode(UsageResponse.self, from: Data(#"""
        {"seven_day_sonnet":{"utilization":1},"seven_day_zeta":{"utilization":1},
         "seven_day_fable":{"utilization":1},"seven_day_opus":{"utilization":1}}
        """#.utf8))
        XCTAssertEqual(r.models.map(\.key), ["opus", "fable", "sonnet", "zeta"])
    }

    func testMicrosecondDateParses() throws {
        XCTAssertNotNil(try decode().fiveHour?.resetsAt)
        XCTAssertNil(try model("sonnet")?.resetsAt)
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
        XCTAssertNil(snapshot.model("opus"))
        XCTAssertEqual(snapshot.model("sonnet")?.percent, 0)
        XCTAssertEqual(snapshot.model("fable")?.percent, 27)
        XCTAssertEqual(snapshot.spendText, "€0.00 / €10.00")
        XCTAssertEqual(snapshot.maxPercent, 27)   // the Fable window is the highest
    }

    /// A snapshot cached by an older build (flat opus/sonnet fields) still loads.
    func testLegacySnapshotMigrates() throws {
        let legacy = """
        {"sessionPercent":10,"weeklyPercent":20,"opusPercent":45,"sonnetPercent":5,
         "fetchedAt":0}
        """
        let snapshot = try JSONDecoder().decode(UsageSnapshot.self, from: Data(legacy.utf8))
        XCTAssertEqual(snapshot.models.map(\.key), ["opus", "sonnet"])
        XCTAssertEqual(snapshot.model("opus")?.percent, 45)
        XCTAssertEqual(snapshot.maxPercent, 45)
    }

    /// Round-tripping keeps the model windows.
    func testSnapshotRoundTrip() throws {
        let reset = Date(timeIntervalSince1970: 1_750_000_000)
        let original = UsageSnapshot(
            sessionPercent: 5, sessionResetsAt: reset,
            weeklyPercent: 40, weeklyResetsAt: reset,
            models: [ModelUsage(key: "fable", percent: 27, resetsAt: reset)],
            spendUsed: 1, spendLimit: 10, spendCurrency: "EUR",
            fetchedAt: Date(timeIntervalSince1970: 1_749_000_000))
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(UsageSnapshot.self, from: data), original)
    }

    /// Per-model visibility is driven by the hidden set, so new models show up.
    func testHiddenModelsFilter() throws {
        var settings = Settings()
        XCTAssertEqual(UsageSnapshot.sample.visibleModels(settings).map(\.key),
                       ["opus", "fable", "sonnet"])
        settings.hiddenModels = ["opus"]
        XCTAssertEqual(UsageSnapshot.sample.visibleModels(settings).map(\.key),
                       ["fable", "sonnet"])
        settings.showSecondary = false
        XCTAssertTrue(UsageSnapshot.sample.visibleModels(settings).isEmpty)
    }

    func testFractionUtilizationClamped() throws {
        // A 0...1 style value should still be treated as a percent (clamped 0...100).
        let r = try JSONDecoder().decode(UsageResponse.self,
            from: Data(#"{"five_hour":{"utilization":150}}"#.utf8))
        XCTAssertEqual(r.fiveHour?.percentUsed, 100)
    }
}
