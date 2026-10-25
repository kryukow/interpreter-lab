import SwiftUI

enum LabBudgetFormat {
    static func usd(_ value: Double, precise: Bool = false) -> String {
        if !precise, value > 0, value < 0.01 { return "<$0.01" }
        return String(format: precise ? "$%.4f" : "$%.2f", value)
    }
    static func credits(_ value: Int) -> String { value.formatted(.number.grouping(.automatic)) }
}

struct LabSphereBudget: View {
    @ObservedObject var model: LabSession
    @ObservedObject private var budget = LabAccountBudget.shared
    let open: () -> Void
    private var value: String {
        switch model.speechEngine {
        case "elevenlabs": return budget.eleven.map { LabBudgetFormat.credits($0.remaining) } ?? "—"
        case "openai": return budget.ledger.estimatedRemaining.map { LabBudgetFormat.usd($0) } ?? "—"
        default: return "0"
        }
    }
    var body: some View {
        Button(action: open) {
            Text(value)
                .font(.system(size: 25, weight: .ultraLight))
                .monospacedDigit().tracking(-0.6)
                .foregroundStyle(Color(red: 0.72, green: 0.78, blue: 0.83).opacity(0.42))
                .minimumScaleFactor(0.65).lineLimit(1)
                .frame(width: 106, height: 60)
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel(model.speechEngine == "openai" ? "OpenAI. Расчётный остаток \(value)" : model.speechEngine == "elevenlabs" ? "ElevenLabs. Остаток \(value) кредитов" : "Apple Voice. Озвучивание бесплатно")
            .accessibilityHint("Открыть остаток и расходы")
            .task(id: model.speechEngine) {
                budget.reloadLedger()
                if model.speechEngine == "elevenlabs" { await budget.refreshEleven() }
            }
    }
}

struct LabBudgetMeter: View {
    @ObservedObject var model: LabSession
    @ObservedObject private var budget = LabAccountBudget.shared
    let open: () -> Void
    private var provider: String { model.speechEngine == "elevenlabs" ? "ELEVENLABS" : model.speechEngine == "openai" ? "OPENAI API" : "APPLE VOICE" }
    private var value: String {
        switch model.speechEngine {
        case "elevenlabs": return budget.eleven.map { LabBudgetFormat.credits($0.remaining) + " кр." } ?? "—"
        case "openai": return budget.ledger.estimatedRemaining.map { "≈ " + LabBudgetFormat.usd($0) } ?? "Задать баланс"
        default: return "Без расходов"
        }
    }
    private var note: String {
        switch model.speechEngine {
        case "elevenlabs":
            if budget.loading { return "Обновляю остаток…" }
            if !budget.elevenError.isEmpty { return budget.eleven == nil ? "Нужна проверка доступа" : "Сохранено · не обновлено" }
            return budget.elevenDate.map { "Данные сервиса · " + $0.formatted(date: .omitted, time: .shortened) } ?? "Остаток лимита аккаунта"
        case "openai": return budget.ledger.unknownRequests > 0 ? "Расчёт Lab · есть неучтённые запросы" : "Расчёт Lab · нажми, чтобы сверить"
        default: return model.authSource == "api" ? "Озвучивание бесплатно · перевод API отдельно" : "Системное озвучивание iPhone"
        }
    }
    private var fraction: Double {
        if model.speechEngine == "elevenlabs" { return budget.eleven?.fraction ?? 0 }
        if model.speechEngine == "openai", let anchor = budget.ledger.anchorUSD, anchor > 0 { return min(1, (budget.ledger.estimatedRemaining ?? 0) / anchor) }
        return model.speechEngine == "apple" ? 1 : 0
    }
    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(provider).font(.system(size: 8, design: .monospaced)).tracking(1.5).foregroundStyle(.white.opacity(0.45))
                    Spacer(minLength: 0)
                    Text(value).font(.system(size: 14, weight: .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.86))
                    Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(.white.opacity(0.3))
                }
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.045))
                        Capsule().fill(LinearGradient(colors: [.white.opacity(0.13), .white.opacity(0.53)], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(0, geometry.size.width * fraction))
                    }
                }.frame(height: 2)
                Text(note).font(.system(size: 9, design: .monospaced)).foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.padding(.horizontal, 14).padding(.vertical, 12)
                .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 14))
                .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.07), lineWidth: 0.5) }
        }.buttonStyle(.plain)
            .accessibilityLabel("\(provider). \(value). \(note)")
            .task(id: model.speechEngine) {
                budget.reloadLedger()
                if model.speechEngine == "elevenlabs" { await budget.refreshEleven() }
            }
    }
}

struct LabBudgetControls: View {
    @ObservedObject var model: LabSession
    var focused = false
    @ObservedObject private var budget = LabAccountBudget.shared
    @State private var balanceInput = ""
    @State private var message = ""
    private var amount: Double? {
        let clean = balanceInput.replacingOccurrences(of: ",", with: ".").filter { !$0.isWhitespace }
        guard let value = Double(clean), value.isFinite, value >= 0, value <= 1_000_000 else { return nil }
        return value
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !focused || model.speechEngine != "openai" {
            VStack(alignment: .leading, spacing: 12) {
                heading("ELEVENLABS", "Остаток лимита")
                Text(budget.eleven.map { LabBudgetFormat.credits($0.remaining) + " кредитов" } ?? "—")
                    .font(.system(size: 25, weight: .light, design: .monospaced))
                if let value = budget.eleven {
                    Text("Использовано \(LabBudgetFormat.credits(value.characterCount)) из \(LabBudgetFormat.credits(value.characterLimit)) · \(value.tier)")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let reset = value.nextReset, reset > 0 {
                        Text("Обновление лимита: \(Date(timeIntervalSince1970: reset).formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if value.canExtend == true { Text("У аккаунта может быть разрешён расход сверх лимита с доплатой.").font(.caption).foregroundStyle(.secondary) }
                }
                if let date = budget.elevenDate {
                    Text("Данные ElevenLabs от \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                }
                if !budget.elevenError.isEmpty { Text(budget.elevenError).font(.footnote).foregroundStyle(.orange) }
                Button { Task { await budget.refreshEleven(force: true) } } label: {
                    HStack { if budget.loading { ProgressView().controlSize(.small) }; Label(budget.loading ? "Обновляю…" : "Обновить остаток", systemImage: "arrow.clockwise") }
                }.disabled(budget.loading || !model.elevenKeySaved)
                Text("Получение остатка не создаёт платного аудио. Нужен доступ к данным пользователя: User → Read (user_read). При ошибке показываются прежние данные с датой.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(18).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 18))
            }

            if !focused || model.speechEngine != "elevenlabs" {
            VStack(alignment: .leading, spacing: 13) {
                heading("OPENAI API", "Расчётный остаток")
                Text(budget.ledger.estimatedRemaining.map { "≈ " + LabBudgetFormat.usd($0) } ?? "Баланс ещё не задан")
                    .font(.system(size: 25, weight: .light, design: .monospaced))
                Text("\(budget.ledger.anchorDate == nil ? "Учтённый расход Lab" : "Расход Lab после сверки"): ≈ \(LabBudgetFormat.usd(budget.ledger.spentUSD, precise: true))")
                    .font(.footnote).foregroundStyle(.secondary)
                if let date = budget.ledger.anchorDate {
                    Text("Сверен вручную: \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                }
                if budget.ledger.unknownRequests > 0 {
                    Text("Запросов без полной стоимости: \(budget.ledger.unknownRequests). Расчёт может завышать остаток — сверь сумму с кабинетом OpenAI.")
                        .font(.footnote).foregroundStyle(.orange)
                }
                Link("Открыть баланс OpenAI", destination: URL(string: "https://platform.openai.com/settings/organization/billing/overview")!)
                    .font(.footnote)
                TextField("Текущий баланс из кабинета, USD", text: $balanceInput)
                    .keyboardType(.decimalPad).padding(13).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
                Button("Сохранить текущий баланс") {
                    guard let amount else { return }
                    do { try budget.setOpenAIBalance(amount); balanceInput = ""; message = "Баланс сохранён. Новый расчёт начинается с этой суммы." }
                    catch { message = error.localizedDescription }
                }.disabled(amount == nil || !model.keySaved)
                if !model.keySaved { Text("Сначала сохрани OpenAI API-ключ в настройках.").font(.footnote).foregroundStyle(.secondary) }
                if !message.isEmpty { Text(message).font(.footnote).foregroundStyle(.secondary) }
                Text("Это оценка Lab по usage из ответов API и тарифам от 20.10.2026. Учитываются новые запросы перевода API, озвучивания OpenAI, платные пробы и оценка транскрибации по длительности. Расходы до установки счётчика, другие приложения, налоги, скидки и пополнения автоматически не видны. После сверки расход отсчитывается заново; сохранённое аудио повторно не списывается.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("При обрыве без usage или неизвестном тарифе показывается отметка о неполном расчёте. Смена API-ключа требует новой сверки. Подписка ChatGPT в денежном счётчике не учитывается.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(18).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 18))
            }
        }.task { budget.reloadLedger(); if model.elevenKeySaved { await budget.refreshEleven() } }
    }
    private func heading(_ label: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).font(.system(size: 9, design: .monospaced)).tracking(2).foregroundStyle(.secondary)
            Text(title).font(.system(size: 17, weight: .medium))
        }
    }
}

struct LabBudgetSheet: View {
    @ObservedObject var model: LabSession
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView { LabBudgetControls(model: model, focused: true).padding(20) }
                .background(Color(red: 0.035, green: 0.039, blue: 0.047))
                .navigationTitle("Остаток и расходы").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }.tint(.white).preferredColorScheme(.dark)
    }
}
