import Foundation
import CryptoKit

/// Price snapshot: official model pages, 2026-10-20. Values are USD per 1M
/// tokens. This is a local estimate, never a provider-reported wallet balance.
enum LabUsagePrice {
    static func cost(model: String, usage: [String: Any]) -> Double? {
        func count(_ source: [String: Any], _ key: String) -> Int? {
            guard let value = source[key] as? Int, value >= 0, value <= 1_000_000_000 else { return nil }
            return value
        }
        guard let input = count(usage, "input_tokens"), let output = count(usage, "output_tokens") else { return nil }
        if LabOpenAISpeech.supports(model) {
            guard let incoming = usage["input_token_details"] as? [String: Any],
                  let outgoing = usage["output_token_details"] as? [String: Any],
                  let textIn = count(incoming, "text_tokens"), let audioIn = count(incoming, "audio_tokens"),
                  let textOut = count(outgoing, "text_tokens"), let audioOut = count(outgoing, "audio_tokens"),
                  textIn + audioIn == input, textOut + audioOut == output else { return nil }
            let cached = count(incoming, "cached_tokens") ?? 0
            let details = incoming["cached_tokens_details"] as? [String: Any] ?? [:]
            let cachedText = count(details, "text_tokens") ?? (audioIn == 0 ? cached : 0)
            let cachedAudio = count(details, "audio_tokens") ?? 0
            guard cachedText + cachedAudio == cached, cachedText <= textIn, cachedAudio <= audioIn else { return nil }
            let mini = model == LabOpenAISpeech.mini
            let amount = Double(textIn - cachedText) * (mini ? 0.60 : 4)
                + Double(cachedText) * (mini ? 0.06 : 0.40)
                + Double(audioIn - cachedAudio) * (mini ? 10 : 32)
                + Double(cachedAudio) * (mini ? 0.30 : 0.40)
                + Double(textOut) * (mini ? 2.40 : 24)
                + Double(audioOut) * (mini ? 20 : 64)
            return amount / 1_000_000
        }
        let rates: (Double, Double, Double)
        switch model {
        case "gpt-4.1": rates = (2, 0.50, 8)
        case "gpt-4.1-mini": rates = (0.40, 0.10, 1.60)
        default: return nil
        }
        let details = usage["input_tokens_details"] as? [String: Any] ?? [:]
        let cached = count(details, "cached_tokens") ?? 0
        guard cached <= input else { return nil }
        return (Double(input - cached) * rates.0 + Double(cached) * rates.1 + Double(output) * rates.2) / 1_000_000
    }
}

struct LabOpenAILedger: Codable {
    var scope = ""
    var anchorUSD: Double?
    var anchorDate: Date?
    var spentUSD = 0.0
    var unknownRequests = 0
    var seenIDs: [String] = []
    var estimatedRemaining: Double? { anchorUSD.map { max(0, $0 - spentUSD) } }
    mutating func anchor(_ amount: Double, date: Date = Date()) {
        guard amount.isFinite, amount >= 0, amount <= 1_000_000 else { return }
        anchorUSD = amount; anchorDate = date; spentUSD = 0; unknownRequests = 0
        // Keep request IDs: resetting a baseline must not count a duplicate event.
    }
    mutating func record(id: String, cost: Double?) {
        guard !seenIDs.contains(id) else { return }
        seenIDs.append(id)
        if seenIDs.count > 1000 { seenIDs.removeFirst(seenIDs.count - 1000) }
        if let cost, cost.isFinite, cost >= 0 { spentUSD += cost }
        else { unknownRequests += 1 }
    }
}

/// Serializes writes from the translation stream and speech socket. Stores only
/// totals and opaque response IDs, never API keys, speech or translated text.
enum LabSpendJournal {
    private static let lock = NSLock()
    private static let storage = "lab.openAIUsage.v1"
    static func scope(_ key: String) -> String {
        SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func read(apiKey: String?, defaults: UserDefaults = .standard) -> LabOpenAILedger {
        guard let apiKey, !apiKey.isEmpty else { return LabOpenAILedger() }
        let scope = scope(apiKey)
        if let data = defaults.data(forKey: storage + "." + scope), let value = try? JSONDecoder().decode(LabOpenAILedger.self, from: data), value.scope == scope { return value }
        var value = LabOpenAILedger(); value.scope = scope; return value
    }
    static func anchor(_ amount: Double, apiKey: String, defaults: UserDefaults = .standard) {
        lock.lock()
        var value = read(apiKey: apiKey, defaults: defaults); value.anchor(amount)
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: storage + "." + value.scope) }
        lock.unlock()
        NotificationCenter.default.post(name: LabBudgetEvents.changed, object: nil)
    }
    static func record(id: String, model: String, usage: [String: Any]?, apiKey: String, defaults: UserDefaults = .standard) {
        lock.lock()
        var value = read(apiKey: apiKey, defaults: defaults)
        value.record(id: id, cost: usage.flatMap { LabUsagePrice.cost(model: model, usage: $0) })
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: storage + "." + value.scope) }
        lock.unlock()
        NotificationCenter.default.post(name: LabBudgetEvents.changed, object: nil)
    }
}
