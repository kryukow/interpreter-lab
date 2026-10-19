import SwiftUI
import UIKit
import SafariServices

@main
struct InterpreterLabApp: App {
    var body: some Scene {
        WindowGroup { LabView().preferredColorScheme(.dark) }
    }
}

// The header, orbit animation, gesture logic and microphone Canvas are sourced
// from Interpreter Live 1.4.23. Only the app title and data/gesture callbacks
// are connected to Lab's non-Realtime translation pipeline.
struct LabView: View {
    @StateObject private var model = LabSession()
    @State private var settings = false
    @AppStorage("lab.keepAwake") private var keepAwake = true
    @AppStorage("lab.partnerLanguage") private var partnerCode = "de"
    @State private var orbitActive = false
    @State private var orbitDragStart = 0
    @State private var orbitStarted = false
    @State private var orbitHide: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase

    private var partner: PartnerLanguage { PartnerLanguage.current(partnerCode) }
    private var languages: [PartnerLanguage] { PartnerLanguage.allCases }
    private var canChangeLanguage: Bool { model.phase == .idle && model.held == nil }
    private var resonancePhase: LabResonancePhase {
        switch model.phase {
        case .recording: return .input
        case .recognizing, .translating, .preparingVoice: return .processing
        case .playing: return .output
        case .idle, .arming: return .idle
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 11) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("INTERPRETER LAB")
                            .font(.system(size: 10, weight: .medium))
                            .tracking(3.2)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 7) {
                            Text("Русский ↔")
                                .font(.title2.bold())
                                .fixedSize()
                            Text(partner.name)
                                .font(.title2.bold())
                                .lineLimit(1)
                                .minimumScaleFactor(0.73)
                                .contentShape(Rectangle())
                                .gesture(languageDrag)
                                .accessibilityLabel("Язык: \(partner.name). Проведи пальцем влево или вправо")
                                .accessibilityAddTraits(.isButton)
                        }
                    }
                    Spacer(minLength: 6)
                    Button { model.stopAll(); settings = true } label: {
                        Image(systemName: "gearshape")
                            .font(.title2.weight(.medium))
                            .frame(width: 36, height: 36)
                    }
                    .disabled(!canChangeLanguage)
                    .accessibilityLabel("Настройки")
                }
                .padding(.top, 12)

                ZStack {
                    LabGraphiteSignalView(
                        signal: model.visualSignal,
                        phase: resonancePhase,
                        orbitActive: orbitActive
                    )
                    .frame(height: 168)
                    .accessibilityHidden(true)

                    ForEach(languages) { choice in
                        let distance = cyclicDistance(for: choice)
                        let active = distance == 0
                        Button {
                            selectLanguage(choice)
                            scheduleOrbitHide(after: 0.65)
                        } label: {
                            Text(choice.shortCode)
                                .font(.system(size: active ? 24 : 19, weight: .bold))
                                .foregroundStyle(active ? Color.black : Color.white)
                                .frame(width: active ? 65 : 47, height: active ? 58 : 50)
                                .background(
                                    active ? Color(white: 0.91) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 18)
                                )
                                .opacity(active ? 1 : abs(distance) == 1 ? 0.72 : 0.28)
                                .scaleEffect(active ? 1 : abs(distance) == 1 ? 0.90 : 0.70)
                        }
                        .buttonStyle(.plain)
                        .offset(x: CGFloat(distance) * 70)
                        .opacity(orbitActive ? 1 : 0)
                        .allowsHitTesting(orbitActive && canChangeLanguage)
                        .accessibilityLabel(choice.name)
                    }
                    Text("\(partner.shortCode) · \(partner.name) · выбрано")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .offset(y: 49)
                        .opacity(orbitActive ? 1 : 0)
                }
                .frame(height: 168)
                .animation(.spring(response: 0.33, dampingFraction: 0.83), value: orbitActive)
                .animation(.spring(response: 0.29, dampingFraction: 0.85), value: partnerCode)
                .sensoryFeedback(.selection, trigger: partnerCode)

                LabWaveformSignalView(signal: model.visualSignal, recording: model.phase == .recording || model.phase == .playing)
                    .frame(height: 23)

                VStack(spacing: 3) {
                    Text(model.message)
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                    if model.phase == .recording {
                        Text(String(format: "● %.1f с", model.elapsed))
                            .font(.caption.monospacedDigit())
                    }
                    if model.busy && model.phase != .recording && model.phase != .arming {
                        Button("Остановить") { model.stopAll() }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }.frame(minHeight: 27)

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("РАСПОЗНАВАНИЕ").font(.caption2).foregroundStyle(.secondary)
                        Text("Apple Speech").font(.subheadline.bold())
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("ПЕРЕВОД").font(.caption2).foregroundStyle(.secondary)
                        Text(model.authSource == "chatgpt" ? "ChatGPT Plus" : "OpenAI API")
                            .font(.subheadline.bold())
                    }
                }
                .padding(16)
                .background(Color(white: 0.07), in: RoundedRectangle(cornerRadius: 22))

                HStack(spacing: 12) {
                    talk("Русский", language: "ru", target: "→ \(partner.uppercaseName)")
                    talk(partner.buttonName, language: partner.rawValue, target: "→ РУССКИЙ")
                }.frame(height: 136)

                Text("Держи → вибросигнал → говори → отпусти")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 12) {
                    Text("ГОЛОСОВОЙ ПЕРЕВОД · LAB")
                        .font(.caption).foregroundStyle(.secondary)

                    Text("РАСПОЗНАНО · \(model.language == "ru" ? "РУССКИЙ" : partner.uppercaseName)")
                        .font(.caption2).foregroundStyle(.secondary)
                    TextEditor(text: $model.source)
                        .frame(minHeight: 65, maxHeight: 120)
                        .scrollContentBackground(.hidden)
                        .disabled(model.busy)
                        .overlay(alignment: .topLeading) {
                            if model.source.isEmpty {
                                Text("Говори или введи текст вручную")
                                    .font(.footnote).foregroundStyle(.secondary)
                                    .padding(.top, 8).padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }

                    Button("Перевести текст") { model.translate() }
                        .disabled(model.busy || model.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Divider()
                    Text("ПЕРЕВОД").font(.caption2).foregroundStyle(.secondary)
                    Text(model.translation.isEmpty ? "—" : model.translation)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(model.replayCaption) { model.replay() }
                        .disabled(!model.canReplay)
                    if !model.detail.isEmpty {
                        Text(model.detail).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(white: 0.075), in: RoundedRectangle(cornerRadius: 16))

                Text(model.version).font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(Color.black)
        .tint(.white)
        .sheet(isPresented: $settings) { LabSettings(model: model) }
        .onAppear { model.setPartner(partner); updateAwake() }
        .onDisappear {
            orbitHide?.cancel()
            UIApplication.shared.isIdleTimerDisabled = false
            model.stopAll()
        }
        .onChange(of: partnerCode) { _, value in
            model.setPartner(PartnerLanguage.current(value))
        }
        .onChange(of: keepAwake) { _, _ in updateAwake() }
        .onChange(of: scenePhase) { _, phase in
            updateAwake()
            if phase != .active { model.stopAll() }
        }
    }

    /// Circular positions keep the selected language at the exact centre.
    private func cyclicDistance(for choice: PartnerLanguage) -> Int {
        guard let center = languages.firstIndex(of: partner),
              let index = languages.firstIndex(of: choice) else { return 0 }
        let distance = (index - center + languages.count) % languages.count
        return distance <= languages.count / 2 ? distance : distance - languages.count
    }

    /// Only the foreign language label captures gestures. Russian never moves.
    private var languageDrag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard canChangeLanguage else { return }
                if !orbitStarted {
                    orbitHide?.cancel()
                    orbitDragStart = languages.firstIndex(of: partner) ?? 0
                    orbitStarted = true
                    withAnimation { orbitActive = true }
                }
                let steps = Int((-value.translation.width / 52).rounded())
                let n = (orbitDragStart + steps % languages.count + languages.count) % languages.count
                selectLanguage(languages[n])
            }
            .onEnded { value in
                orbitStarted = false
                scheduleOrbitHide(after: abs(value.translation.width) < 8 ? 3.5 : 0.6)
            }
    }

    private func selectLanguage(_ choice: PartnerLanguage) {
        guard canChangeLanguage else { return }
        partnerCode = choice.rawValue
        model.setPartner(choice)
    }

    private func scheduleOrbitHide(after seconds: Double) {
        orbitHide?.cancel()
        orbitHide = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            withAnimation { orbitActive = false }
        }
    }

    private func talk(_ title: String, language: String, target: String) -> some View {
        PressButton(title: title, subtitle: target,
                    pressed: model.held == language,
                    enabled: !model.busy || model.held == language,
                    begin: { model.begin(language) },
                    end: { model.end(language) },
                    cancel: { model.abort(language) })
            .frame(maxWidth: .infinity)
    }

    private func updateAwake() {
        UIApplication.shared.isIdleTimerDisabled = keepAwake && scenePhase == .active
    }
}

struct LabSettings: View {
    @ObservedObject var model: LabSession
    @Environment(\.dismiss) private var dismiss
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

    var body: some View {
        NavigationStack {
            Form {
                Section("Способ перевода") {
                    Picker("Использовать", selection: $model.authSource) {
                        Text("Подписка ChatGPT · основной").tag("chatgpt")
                        Text("Платный API · дополнительно").tag("api")
                    }
                    Text(model.authSource == "chatgpt"
                         ? "Перевод текста через Sign in with ChatGPT и лимиты подписки. Отдельный API-ключ не нужен."
                         : "Перевод текста через платный OpenAI API. Вход в ChatGPT для этого режима не требуется.")
                        .font(.footnote)
                }
                if model.authSource == "chatgpt" {
                    Section("ChatGPT") {
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
                            Picker("Модель перевода", selection: $model.chatGPTModel) {
                                Text("Выбери модель").tag("")
                                ForEach(model.chatGPTModels) { item in
                                    Text(item.name).tag(item.id)
                                }
                            }.disabled(authenticating)
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
                    Section("Платный OpenAI API") {
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
                        Picker("Модель API", selection: $model.modelID) {
                            Text("GPT-4.1 mini").tag("gpt-4.1-mini")
                            Text("GPT-4.1").tag("gpt-4.1")
                        }
                    }
                }
                Section("Озвучивание") {
                    Toggle("Автоматически озвучивать перевод", isOn: $model.autoSpeak)
                    Picker("Движок озвучивания", selection: $model.speechEngine) {
                        Text("Apple TTS · без API-расходов").tag("apple")
                        Text("ElevenLabs · облачный голос").tag("elevenlabs")
                    }
                    Text(model.speechEngine == "apple"
                         ? "Apple озвучивает бесплатно и остаётся резервным движком."
                         : "ElevenLabs — отдельный платный API. В ElevenLabs отправляется только готовый перевод. Повторное прослушивание сохранённого звука не создаёт нового запроса.")
                        .font(.footnote)
                    if model.speechEngine == "apple" {
                    Picker("Голос \(model.partner.name)", selection: $model.selectedPartnerVoiceID) {
                        Text("Системный по умолчанию").tag("")
                        ForEach(model.voices(for: model.partner.rawValue), id: \.identifier) { voice in
                            Text("\(voice.name) · \(voice.language)").tag(voice.identifier)
                        }
                    }
                    Picker("Русский голос", selection: $model.russianVoiceID) {
                        Text("Системный по умолчанию").tag("")
                        ForEach(model.voices(for: "ru"), id: \.identifier) { voice in
                            Text("\(voice.name) · \(voice.language)").tag(voice.identifier)
                        }
                    }
                    Text("Голоса Apple доступны без оплаты API. Дополнительные системные голоса можно загрузить в настройках iPhone.")
                        .font(.footnote)
                    }
                }
                if model.speechEngine == "elevenlabs" {
                    Section("ElevenLabs · настройки") {
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
                            if !model.elevenVoices.isEmpty {
                                Picker("Немецкий / \(model.partner.name)", selection: $model.elevenPartnerVoice) {
                                    Text("Выбери голос").tag("")
                                    ForEach(model.elevenVoices) { voice in
                                        Text(voice.name).tag(voice.voiceID)
                                    }
                                }
                                Picker("Русский голос ElevenLabs", selection: $model.elevenRussianVoice) {
                                    Text("Выбери голос").tag("")
                                    ForEach(model.elevenVoices) { voice in
                                        Text(voice.name).tag(voice.voiceID)
                                    }
                                }
                            }
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
                        Picker("Модель генерации", selection: $model.elevenModel) {
                            Text("Flash v2.5 · быстрее и экономичнее").tag(LabElevenModels.fast)
                            Text("Multilingual v2 · естественнее").tag(LabElevenModels.natural)
                        }
                        Text("API-ключу нужны разрешения Voices → Read и Text to Speech. Пока голоса не загружены и не выбраны, ElevenLabs не сможет озвучить перевод. Перед генерацией проверь лимит кредитов.")
                            .font(.footnote)
                        Link("Открыть ElevenLabs", destination: URL(string: "https://elevenlabs.io/app")!)
                    }
                }
                Section("Экран") {
                    Toggle("Не гасить экран", isOn: $keepAwake)
                }
                if !notice.isEmpty {
                    Section { Text(notice).font(.footnote) }
                }
            }
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
            .interactiveDismissDisabled(authenticating)
            .task {
                guard model.authSource == "chatgpt", !model.chatGPTAccount.isEmpty,
                      model.chatGPTModels.isEmpty, !authenticating else { return }
                authenticating = true
                defer { authenticating = false }
                do { try await model.loadChatGPTModels() }
                catch { notice = error.localizedDescription }
            }
            .onDisappear { key = ""; elevenKeyInput = "" }
        }
        .tint(.white)
    }
}

struct LabLoginBrowser: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
