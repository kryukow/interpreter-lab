import XCTest
@testable import InterpreterLab

final class BudgetTests: XCTestCase {
    private var voiceUsage: [String: Any] { [
        "input_tokens": 100, "output_tokens": 220,
        "input_token_details": ["text_tokens": 100, "audio_tokens": 0, "cached_tokens": 40, "cached_tokens_details": ["text_tokens": 40, "audio_tokens": 0]],
        "output_token_details": ["text_tokens": 20, "audio_tokens": 200]
    ] }

    func testRealUsagePricesTextAudioAndCachedTokensSeparately() throws {
        XCTAssertEqual(try XCTUnwrap(LabUsagePrice.cost(model: LabOpenAISpeech.model, usage: voiceUsage)), 0.013536, accuracy: 0.000000001)
        XCTAssertEqual(try XCTUnwrap(LabUsagePrice.cost(model: LabOpenAISpeech.mini, usage: voiceUsage)), 0.0040864, accuracy: 0.000000001)
        let text: [String: Any] = ["input_tokens": 1000, "output_tokens": 200, "input_tokens_details": ["cached_tokens": 400]]
        XCTAssertEqual(try XCTUnwrap(LabUsagePrice.cost(model: "gpt-4.1-mini", usage: text)), 0.0006, accuracy: 0.000000001)
    }

    func testMissingUnknownOrInconsistentUsageCannotBecomeAnExactZeroCost() {
        XCTAssertNil(LabUsagePrice.cost(model: "unknown-model", usage: voiceUsage))
        XCTAssertNil(LabUsagePrice.cost(model: LabOpenAISpeech.model, usage: [:]))
        var bad = voiceUsage; bad["output_tokens"] = 300
        XCTAssertNil(LabUsagePrice.cost(model: LabOpenAISpeech.model, usage: bad))
        bad = voiceUsage; bad["input_tokens"] = -1
        XCTAssertNil(LabUsagePrice.cost(model: LabOpenAISpeech.model, usage: bad))
    }

    func testLedgerDeduplicatesAndRequiresResyncAfterUnknownCosts() {
        var ledger = LabOpenAILedger()
        XCTAssertNil(ledger.estimatedRemaining)
        ledger.anchor(10)
        ledger.record(id: "one", cost: 0.25); ledger.record(id: "one", cost: 0.25)
        XCTAssertEqual(ledger.spentUSD, 0.25)
        XCTAssertEqual(ledger.estimatedRemaining, 9.75)
        ledger.record(id: "interrupted", cost: nil)
        XCTAssertEqual(ledger.unknownRequests, 1)
        ledger.anchor(5)
        XCTAssertEqual(ledger.unknownRequests, 0)
        ledger.record(id: "one", cost: 0.25)
        XCTAssertEqual(ledger.spentUSD, 0)
        ledger.record(id: "large", cost: 6)
        XCTAssertEqual(ledger.estimatedRemaining, 0)
        ledger.record(id: "invalid", cost: .nan)
        XCTAssertEqual(ledger.unknownRequests, 1)
    }

    func testBalancesAreIsolatedByCredentialEvenWithLateOldRequests() throws {
        let suite = "BudgetTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        LabSpendJournal.anchor(10, apiKey: "fixture-account-a", defaults: defaults)
        LabSpendJournal.anchor(20, apiKey: "fixture-account-b", defaults: defaults)
        LabSpendJournal.record(id: "late-a", model: LabOpenAISpeech.model, usage: voiceUsage, apiKey: "fixture-account-a", defaults: defaults)
        XCTAssertEqual(LabSpendJournal.read(apiKey: "fixture-account-b", defaults: defaults).estimatedRemaining, 20)
        let a = LabSpendJournal.read(apiKey: "fixture-account-a", defaults: defaults)
        XCTAssertEqual(try XCTUnwrap(a.estimatedRemaining), 9.986464, accuracy: 0.000000001)
        XCTAssertNil(LabSpendJournal.read(apiKey: nil, defaults: defaults).estimatedRemaining)
        XCTAssertFalse(defaults.dictionaryRepresentation().keys.contains { $0.contains("fixture-account") })
    }

    func testElevenServerQuotaAndOverageAreNotConfusedWithMoney() throws {
        let data = Data(#"{"tier":"starter","character_count":2500,"character_limit":10000,"next_character_count_reset_unix":1800000000,"can_extend_character_limit":true}"#.utf8)
        let quota = try LabElevenAllowance.decode(data)
        XCTAssertEqual(quota.remaining, 7500)
        XCTAssertEqual(quota.fraction, 0.75)
        XCTAssertEqual(quota.nextReset, 1800000000)
        let overage = try LabElevenAllowance.decode(Data(#"{"tier":"starter","character_count":11000,"character_limit":10000}"#.utf8))
        XCTAssertEqual(overage.remaining, 0); XCTAssertEqual(overage.fraction, 0)
        XCTAssertThrowsError(try LabElevenAllowance.decode(Data(#"{"tier":"starter","character_count":-1,"character_limit":10000}"#.utf8)))
        XCTAssertThrowsError(try LabElevenAllowance.decode(Data(#"{"tier":"starter"}"#.utf8)))
    }
}
