import Foundation
import Combine

struct LabElevenAllowance: Codable, Equatable {
    let characterCount: Int
    let characterLimit: Int
    let tier: String
    let nextReset: Double?
    let canExtend: Bool?
    var remaining: Int { max(0, characterLimit - characterCount) }
    var fraction: Double { characterLimit > 0 ? min(1, max(0, Double(remaining) / Double(characterLimit))) : 0 }
    enum CodingKeys: String, CodingKey {
        case tier, characterCount = "character_count", characterLimit = "character_limit"
        case nextReset = "next_character_count_reset_unix", canExtend = "can_extend_character_limit"
    }
    static func decode(_ data: Data) throws -> Self {
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.characterCount >= 0, value.characterLimit >= 0 else { throw LabBudgetError.invalid }
        return value
    }
}

enum LabBudgetError: LocalizedError {
    case invalid, permission, unavailable(Int)
    var errorDescription: String? {
        switch self {
        case .invalid: return "Сервис вернул неполные данные об остатке."
        case .permission: return "Ключ не даёт прочитать остаток. Проверь разрешение User → Read (user_read) в ElevenLabs. Озвучивание при этом может продолжать работать."
        case .unavailable(let code): return "Не удалось обновить остаток ElevenLabs (HTTP \(code))."
        }
    }
}

@MainActor final class LabAccountBudget: NSObject, ObservableObject {
    static let shared = LabAccountBudget()
    private struct Saved: Codable { let scope: String; let value: LabElevenAllowance; let date: Date }
    @Published private(set) var eleven: LabElevenAllowance?
    @Published private(set) var elevenDate: Date?
    @Published private(set) var elevenError = ""
    @Published private(set) var loading = false
    @Published private(set) var ledger = LabOpenAILedger()
    private var activeScope = ""
    private var requestID = UUID()
    private var pendingRefresh: Task<Void, Never>?
    private var lastAttempt = Date.distantPast
    override init() {
        super.init()
        reloadLedger()
        NotificationCenter.default.addObserver(self, selector: #selector(usageChanged), name: LabBudgetEvents.changed, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(elevenCharged), name: LabBudgetEvents.elevenCharged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(credentialsChanged), name: LabBudgetEvents.credentialsChanged, object: nil)
    }
    deinit { NotificationCenter.default.removeObserver(self); pendingRefresh?.cancel() }
    @objc private func usageChanged() { Task { @MainActor [weak self] in self?.reloadLedger() } }
    @objc private func credentialsChanged() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.requestID = UUID(); self.loading = false; self.lastAttempt = .distantPast
            self.eleven = nil; self.elevenDate = nil; self.elevenError = ""; self.activeScope = ""
            self.reloadLedger()
            await self.refreshEleven(force: true)
        }
    }
    @objc private func elevenCharged() {
        Task { @MainActor [weak self] in
            self?.pendingRefresh?.cancel()
            self?.pendingRefresh = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                await self?.refreshEleven(force: true)
            }
        }
    }
    func reloadLedger() { ledger = LabSpendJournal.read(apiKey: try? LabKeychain.load()) }
    func setOpenAIBalance(_ amount: Double) throws {
        guard let key = try LabKeychain.load() else { throw LabOpenAISpeech.SpeechError.noKey }
        guard amount.isFinite, amount >= 0, amount <= 1_000_000 else { throw LabBudgetError.invalid }
        LabSpendJournal.anchor(amount, apiKey: key); reloadLedger()
    }
    func refreshEleven(force: Bool = false) async {
        guard let key = try? LabElevenKeychain.load(), !key.isEmpty else {
            eleven = nil; elevenDate = nil; elevenError = "Добавь ключ ElevenLabs в настройках."; return
        }
        let scope = LabSpendJournal.scope(key)
        if activeScope != scope {
            activeScope = scope; eleven = nil; elevenDate = nil; lastAttempt = .distantPast
            if let data = UserDefaults.standard.data(forKey: "lab.elevenAllowance.v1"), let saved = try? JSONDecoder().decode(Saved.self, from: data), saved.scope == scope {
                eleven = saved.value; elevenDate = saved.date
            }
        }
        guard !loading, force || Date().timeIntervalSince(lastAttempt) > 60 else { return }
        if !force, let date = elevenDate, Date().timeIntervalSince(date) < 300 { return }
        loading = true; lastAttempt = Date(); elevenError = ""
        let token = UUID(); requestID = token
        defer { if requestID == token { loading = false } }
        do {
            var request = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/user/subscription")!)
            request.timeoutInterval = 20
            request.setValue(key, forHTTPHeaderField: "xi-api-key")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard requestID == token, let current = try? LabElevenKeychain.load(), LabSpendJournal.scope(current) == scope else { return }
            guard let http = response as? HTTPURLResponse else { throw LabBudgetError.invalid }
            if http.statusCode == 401 || http.statusCode == 403 { throw LabBudgetError.permission }
            guard (200..<300).contains(http.statusCode) else { throw LabBudgetError.unavailable(http.statusCode) }
            let value = try LabElevenAllowance.decode(data); let date = Date()
            eleven = value; elevenDate = date
            if let saved = try? JSONEncoder().encode(Saved(scope: scope, value: value, date: date)) { UserDefaults.standard.set(saved, forKey: "lab.elevenAllowance.v1") }
        } catch {
            guard requestID == token else { return }
            elevenError = error.localizedDescription
        }
    }
}
