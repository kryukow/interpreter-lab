import SwiftUI
import AVFoundation

struct LabSettings: View {
    @ObservedObject var model: LabSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("lab.keepAwake") private var keepAwake = true
    @State private var key = ""
    @State private var elevenKeyInput = ""
    @State private var elevenBusy = false
    @State private var elevenVoiceStatus = ""
    @State private var elevenVoiceError = false
    @State private var deleteElevenKey = false
    @State private var notice = ""
    @State private var deleteKey = false
    @StateObject private var login = Login()
    @State private var authenticating = false

    @StateObject private var preview = LabVoicePreview()
    @State private var showLibrary = false

    var body: some View {
        NavigationStack {
            ScrollView {
              VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("CONTROL ROOM").font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(3).foregroundStyle(.white.opacity(0.38))
                    Text("Твой переводчик").font(.system(size: 29, weight: .light))
                    Text("Подключение, голоса и поведение. Всё важное — с первого взгляда.").font(.footnote).foregroundStyle(.white.opacity(0.48))
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)

                LabSettingsCard(title: "Перевод", symbol: "arrow.left.arrow.right", summary: translationSummary, initiallyExpanded: true) {
                    LabGraphiteSelectionField(title: "Способ перевода", selection: $model.authSource, choices: [
                        LabGraphiteChoice(id: "chatgpt", title: "Подписка ChatGPT", detail: "Вход через ChatGPT · лимиты твоей подписки", symbol: "person.crop.circle"),
                        LabGraphiteChoice(id: "api", title: "OpenAI API", detail: "Отдельный ключ · оплата API отдельно", symbol: "key.horizontal")
                    ], note: "Перевод отправляет только распознанный текст.")
                    Text(model.authSource == "chatgpt"
                         ? "Перевод текста через Sign in with ChatGPT и лимиты подписки. Отдельный API-ключ не нужен."
                         : "Перевод текста через платный OpenAI API. Вход в ChatGPT для этого режима не требуется.")
                        .font(.footnote)
                }
                if model.authSource == "chatgpt" {
                    LabSettingsCard(title: "Аккаунт ChatGPT", symbol: "person.crop.circle", summary: model.chatGPTAccount.isEmpty ? "Вход не выполнен" : model.chatGPTAccount) {
                        Text(model.chatGPTAccount.isEmpty ? "Вход не выполнен" : "Подключён аккаунт: \(model.chatGPTAccount)")
                            .font(.footnote)
                        if model.chatGPTAccount.isEmpty {
                            Button("Войти через ChatGPT") {
                                authenticating = true
                                notice = ""
                                Task {
                                    defer { authenticating = false }
                                    do {
                                        try await login.signIn()
                                        try await model.loadChatGPTModels()
                                        notice = "ChatGPT подключён. Теперь можно переводить."
                                    } catch { notice = error.localizedDescription }
                                }
                            }.disabled(authenticating)
                        }
                        if !model.chatGPTAccount.isEmpty {
                            Button("Обновить модели") {
                                authenticating = true
                                Task {
                                    defer { authenticating = false }
                                    do { try await model.loadChatGPTModels(); notice = "Список моделей обновлён." }
                                    catch { notice = error.localizedDescription }
                                }
                            }.disabled(authenticating)
                            LabGraphiteSelectionField(title: "Модель перевода", selection: $model.chatGPTModel,
                                choices: model.chatGPTModels.map { LabGraphiteChoice(id: $0.id, title: $0.name, detail: $0.id, symbol: "cpu") },
                                note: "Модели доступны для подключённого аккаунта ChatGPT.")
                                .disabled(authenticating)
                            Button("Выйти из ChatGPT", role: .destructive) {
                                do { try model.disconnectChatGPT(); notice = "Вход ChatGPT удалён только в Lab." }
                                catch { notice = error.localizedDescription }
                            }.disabled(authenticating)
                        }
                        Text("Авторизация использует механизм из основного Interpreter. Сессия Lab хранится отдельно. В OpenAI отправляется только текст, распознанный Apple.")
                            .font(.footnote)
                        if !login.message.isEmpty { Text(login.message).font(.footnote) }
                    }
                }
                if model.authSource == "api" {
                    LabSettingsCard(title: "OpenAI API", symbol: "key.horizontal", summary: model.keySaved ? "Ключ сохранён · \(model.modelID)" : "Ключ не добавлен") {
                        Text(model.keySaved ? "Ключ сохранён в Keychain этого приложения" : "Добавь API-ключ для платного режима")
                            .font(.footnote)
                        SecureField("Вставь API-ключ", text: $key)
                            .textContentType(.password).textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Вставить из буфера") { key = UIPasteboard.general.string ?? "" }
                        Button("Сохранить ключ") {
                            do {
                                try model.saveKey(key)
                                key = ""
                                notice = "API-ключ сохранён"
                            } catch { notice = error.localizedDescription }
                        }.disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if model.keySaved {
                            Button("Удалить ключ", role: .destructive) { deleteKey = true }
                        }
                        Link("Создать ключ OpenAI", destination: URL(string: "https://platform.openai.com/api-keys")!)
                        LabGraphiteSelectionField(title: "Модель API", selection: $model.modelID, choices: [
                            LabGraphiteChoice(id: "gpt-4.1-mini", title: "GPT-4.1 mini", detail: "Компактная модель для перевода", symbol: "cpu"),
                            LabGraphiteChoice(id: "gpt-4.1", title: "GPT-4.1", detail: "Полная модель", symbol: "cpu")
                        ], note: "Запросы оплачиваются отдельно по тарифу OpenAI API.")
                    }
                }
                LabSettingsCard(title: "Голос", symbol: "waveform", summary: speechSummary) {
                    Toggle("Автоматически озвучивать перевод", isOn: $model.autoSpeak)
                    LabGraphiteSelectionField(title: "Движок озвучивания", selection: $model.speechEngine, choices: [
                        LabGraphiteChoice(id: "apple", title: "Apple", detail: "Системные голоса iPhone · без API-расходов", symbol: "iphone"),
                        LabGraphiteChoice(id: "elevenlabs", title: "ElevenLabs", detail: "Облачные голоса · отдельный платный API", symbol: "waveform")
                    ], note: "Голос можно прослушать перед выбором. Демо ElevenLabs не создаёт платную генерацию.")
                    Text(model.speechEngine == "apple"
                         ? "Apple озвучивает бесплатно и остаётся резервным движком."
                         : "ElevenLabs — отдельный платный API. В ElevenLabs отправляется только готовый перевод. Повторное прослушивание сохранённого звука не создаёт нового запроса.")
                        .font(.footnote)
                    if model.speechEngine == "apple" {
                    NavigationLink {
                        LabAppleVoicePicker(title: model.partner.name, language: model.partner.rawValue, voices: model.voices(for: model.partner.rawValue), selection: $model.selectedPartnerVoiceID)
                    } label: { voiceLink("Голос \(model.partner.name)", name: appleName(model.selectedPartnerVoiceID)) }
                    NavigationLink {
                        LabAppleVoicePicker(title: "Русский голос", language: "ru", voices: model.voices(for: "ru"), selection: $model.russianVoiceID)
                    } label: { voiceLink("Русский голос", name: appleName(model.russianVoiceID)) }
                    appleAudition
                    Text("Голоса Apple доступны без оплаты API. Дополнительные системные голоса можно загрузить в настройках iPhone.")
                        .font(.footnote)
                    }
                }
                if model.speechEngine == "elevenlabs" {
                    LabSettingsCard(title: "Студия ElevenLabs", symbol: "slider.horizontal.3", summary: "\(model.elevenModel == LabElevenModels.fast ? "Flash v2.5" : "Multilingual v2") · \(model.elevenKeySaved ? "подключено" : "нужен ключ")\n\(model.elevenAutoGenerate ? "Автогенерация · расход кредитов" : "Генерация вручную")") {
                        Text(model.elevenKeySaved
                             ? "Ключ ElevenLabs сохранён отдельно в Keychain этого iPhone"
                             : "Сначала создай ключ в личном кабинете ElevenLabs, затем вставь его сюда.")
                            .font(.footnote)
                        SecureField("ElevenLabs API-ключ", text: $elevenKeyInput)
                            .textContentType(.password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Сохранить ключ ElevenLabs") {
                            do {
                                try model.saveElevenKey(elevenKeyInput)
                                elevenKeyInput = ""
                                elevenVoiceStatus = "Ключ сохранён. Теперь нажми «Загрузить доступные голоса»."
                                elevenVoiceError = false
                                notice = ""
                            } catch { notice = error.localizedDescription }
                        }
                        .disabled(elevenBusy || elevenKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if model.elevenKeySaved {
                            Button("Загрузить доступные голоса") {
                                elevenBusy = true
                                elevenVoiceStatus = "Обращаюсь к ElevenLabs…"
                                elevenVoiceError = false
                                notice = ""
                                Task {
                                    defer { elevenBusy = false }
                                    do {
                                        try await model.loadElevenVoices()
                                        let count = model.elevenVoices.count
                                        if count == 0 {
                                            elevenVoiceError = true
                                            elevenVoiceStatus = "ElevenLabs ответил, но доступных голосов нет. Проверь разрешение Voices → Read и наличие голосов в личном кабинете."
                                        } else {
                                            elevenVoiceStatus = "ElevenLabs подключён ✓ Загружено голосов: \(count). Ниже выбери русский и \(model.partner.name) голоса."
                                        }
                                    } catch {
                                        elevenVoiceError = true
                                        elevenVoiceStatus = "Не удалось загрузить голоса: \(error.localizedDescription)"
                                    }
                                }
                            }.disabled(elevenBusy)
                            if elevenBusy {
                                ProgressView("Загружаю голоса ElevenLabs…")
                            }
                            if !elevenVoiceStatus.isEmpty {
                                Text(elevenVoiceStatus)
                                    .font(.footnote)
                                    .foregroundStyle(elevenVoiceError ? Color.orange : Color.secondary)
                            }
                                NavigationLink {
                                    LabOwnedVoicePicker(model: model, title: model.partner.name, language: model.partner.rawValue, selection: $model.elevenPartnerVoice)
                                } label: { voiceLink(model.partner.name, name: elevenName(model.elevenPartnerVoice)) }
                                NavigationLink {
                                    LabOwnedVoicePicker(model: model, title: "Русский голос", language: "ru", selection: $model.elevenRussianVoice)
                                } label: { voiceLink("Русский голос", name: elevenName(model.elevenRussianVoice)) }

                            Button { showLibrary = true } label: {
                                Label("Библиотека голосов · прослушать и выбрать", systemImage: "play.circle")
                            }
                            ownedAudition
                            Button("Удалить ключ ElevenLabs", role: .destructive) {
                                deleteElevenKey = true
                            }.disabled(elevenBusy)
                        }
                        Toggle("Автогенерация ElevenLabs (расход кредитов)",
                               isOn: $model.elevenAutoGenerate)
                        Text(model.elevenAutoGenerate
                             ? "После каждого перевода ElevenLabs будет автоматически генерировать платное аудио."
                             : "Автоматическая платная генерация отключена. Можно проверить голос вручную кнопкой «Озвучить» после перевода.")
                            .font(.footnote)
                        LabGraphiteSelectionField(title: "Модель генерации", selection: $model.elevenModel, choices: [
                            LabGraphiteChoice(id: LabElevenModels.fast, title: "Flash v2.5", detail: "Быстрее и экономичнее", symbol: "bolt"),
                            LabGraphiteChoice(id: LabElevenModels.natural, title: "Multilingual v2", detail: "Естественнее · многоязычная речь", symbol: "waveform")
                        ], note: "Генерация расходует кредиты ElevenLabs. Прослушивание готового демо не расходует кредиты генерации.")
                        Text("Для списка и демо нужно Voices → Read. Для добавления из библиотеки включи Voices → Write (voices_write). Для генерации перевода нужно Text to Speech. Сохранённые голоса остаются выбранными после перезапуска; обновление списка не меняет выбор. Перед генерацией проверь лимит кредитов.")
                            .font(.footnote)
                        Link("Открыть ElevenLabs", destination: URL(string: "https://elevenlabs.io/app")!)
                    }
                }
                LabSettingsCard(title: "Поведение", symbol: "iphone", summary: keepAwake ? "Экран остаётся включённым" : "Системное время блокировки") {
                    Toggle("Не гасить экран", isOn: $keepAwake)
                }
                if !notice.isEmpty {
                    Text(notice).font(.footnote).foregroundStyle(.white.opacity(0.7)).frame(maxWidth: .infinity, alignment: .leading).padding(16).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18))
                }
              }.padding(.horizontal, 20).padding(.bottom, 30)
            }
            .background(Color(red: 0.035, green: 0.039, blue: 0.047))
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { key = ""; elevenKeyInput = ""; dismiss() }
                        .disabled(authenticating || elevenBusy)
                }
            }
            .confirmationDialog("Удалить API-ключ из этого приложения?", isPresented: $deleteKey) {
                Button("Удалить", role: .destructive) {
                    do { try model.deleteKey(); notice = "Ключ удалён" }
                    catch { notice = error.localizedDescription }
                }
            }
            .confirmationDialog("Удалить отдельный API-ключ ElevenLabs?", isPresented: $deleteElevenKey) {
                Button("Удалить ключ ElevenLabs", role: .destructive) {
                    do {
                        try model.deleteElevenKey()
                        elevenVoiceStatus = ""
                        elevenVoiceError = false
                        notice = "Ключ ElevenLabs удалён, снова используется Apple TTS."
                    }
                    catch { notice = error.localizedDescription }
                }
            }
            .sheet(isPresented: Binding(get: { login.browserURL != nil }, set: { _ in })) {
                if let url = login.browserURL {
                    LabLoginBrowser(url: url).interactiveDismissDisabled()
                }
            }
            .sheet(isPresented: $showLibrary) {
                LabVoiceLibrary(model: model)
            }
            .interactiveDismissDisabled(authenticating)
            .task {
                guard model.authSource == "chatgpt", !model.chatGPTAccount.isEmpty,
                      model.chatGPTModels.isEmpty, !authenticating else { return }
                authenticating = true
                defer { authenticating = false }
                do { try await model.loadChatGPTModels() }
                catch { notice = error.localizedDescription }
            }
            .onDisappear { key = ""; elevenKeyInput = ""; preview.stop() }
            .onChange(of: scenePhase) { _, phase in if phase != .active { preview.stop() } }
            .onChange(of: model.speechEngine) { _, _ in preview.stop() }
        }
        .tint(.white)
        .preferredColorScheme(.dark)
    }
    private var translationSummary: String {
        model.authSource == "chatgpt"
          ? "ChatGPT · \(model.chatGPTModel.isEmpty ? "модель не выбрана" : model.chatGPTModel)"
          : "OpenAI API · \(model.modelID)"
    }
    private var speechSummary: String {
        let engine = model.speechEngine == "apple" ? "Apple" : "ElevenLabs"
        let russian = model.speechEngine == "apple" ? appleName(model.russianVoiceID) : elevenName(model.elevenRussianVoice)
        let partner = model.speechEngine == "apple" ? appleName(model.selectedPartnerVoiceID) : elevenName(model.elevenPartnerVoice)
        return "\(engine) · \(model.autoSpeak ? "авто" : "вручную")\nRU: \(russian) · \(model.partner.rawValue.uppercased()): \(partner)"
    }
    private func appleName(_ id: String) -> String {
        AVSpeechSynthesisVoice(identifier: id)?.name ?? "Системный"
    }
    private func elevenName(_ id: String) -> String {
        let names = UserDefaults.standard.dictionary(forKey: "lab.elevenVoiceNames") as? [String: String] ?? [:]
        return model.elevenVoices.first { $0.voiceID == id }?.name
          ?? names[id]
          ?? (id.isEmpty ? "не выбран" : "выбран · обнови список")
    }
    private func voiceLink(_ title: String, name: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) { Text(title); Text(name).font(.caption).foregroundStyle(.secondary) }
            Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }
    private var appleAudition: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Проба выбранных голосов").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button { preview.playApple(voiceID: model.russianVoiceID, language: "ru") } label: { Label("Русский", systemImage: "play.circle") }
                Spacer()
                Button { preview.playApple(voiceID: model.selectedPartnerVoiceID, language: model.partner.rawValue) } label: { Label(model.partner.name, systemImage: "play.circle") }
            }
            previewFeedback
        }
    }
    private var ownedAudition: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Прослушай демо перед выбором в библиотеке. Прослушивание готового демо не генерирует платную речь.").font(.footnote).foregroundStyle(.secondary)
            previewFeedback
        }
    }
    @ViewBuilder private var previewFeedback: some View {
        if preview.isLoading { ProgressView("Открываю демо…") }
        if preview.activeID != nil { Button("Остановить пробу") { preview.stop() } }
        if let error = preview.errorMessage { Text(error).font(.footnote).foregroundStyle(.orange) }
    }

}


