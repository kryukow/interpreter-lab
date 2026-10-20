import SwiftUI
import AVFoundation

struct LabVoiceLibrary: View {
    @ObservedObject var model: LabSession
    var initialLanguage: String? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var preview = LabVoicePreview()
    @State private var language = "en"
    @State private var search = ""
    @State private var voices: [LabSharedVoice] = []
    @State private var busy = false
    @State private var importing: String?
    @State private var status = ""
    @State private var page = 0
    @State private var hasMore = false
    @State private var requestID = UUID()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    Text("VOICE LIBRARY").font(.system(size: 10, design: .monospaced)).tracking(3).foregroundStyle(.secondary)
                    Text("Сначала послушай.").font(.system(size: 28, weight: .light))
                    Text("Это общая библиотека ElevenLabs, а не только голоса твоего аккаунта. Готовые записи бесплатны; создание пробы на нужном языке — отдельное действие с расходом кредитов. Прослушивание не добавляет и не выбирает голос.")
                        .font(.footnote).foregroundStyle(.secondary)
                    LabGraphiteSelectionField(title: "Язык голоса", selection: $language,
                        choices: LabElevenCatalogAPI.languages.map {
                            LabGraphiteChoice(id: $0.code, title: $0.name, detail: $0.code.uppercased(), symbol: "globe")
                        }, note: "Язык фильтрует библиотеку. Готовая проба может звучать на другом языке.")
                        .disabled(importing != nil)
                    HStack {
                        TextField("Имя, акцент или описание", text: $search).textInputAutocapitalization(.never)
                            .submitLabel(.search).onSubmit { refresh() }
                        Button { refresh() } label: { Image(systemName: "magnifyingglass") }.disabled(busy)
                    }.padding(14).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 15))
                    if busy && voices.isEmpty { ProgressView("Ищу голоса…").frame(maxWidth: .infinity).padding(25) }
                    if !busy && voices.isEmpty && status.isEmpty {
                        Text("Голосов не найдено. Попробуй другое имя или язык.").font(.footnote).foregroundStyle(.secondary)
                    }
                    if !status.isEmpty { Text(status).font(.footnote).foregroundStyle(.white.opacity(0.7)) }
                    if !voices.isEmpty {
                        Text("ОБЩАЯ БИБЛИОТЕКА · ПОКАЗАНО \(voices.count)")
                            .font(.system(size: 10, design: .monospaced)).tracking(1).foregroundStyle(.secondary)
                    }
                    if let error = preview.errorMessage { Text(error).font(.footnote).foregroundStyle(.orange) }
                    ForEach(voices) { voice in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(voice.name).font(.system(size: 17, weight: .medium))
                                    Text([voice.gender, voice.accent].compactMap { $0 }.joined(separator: " · "))
                                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            LabVoiceAuditionControls(preview: preview, voiceID: voice.voiceID,
                                language: language, modelID: model.elevenModel,
                                recordedURL: voice.preview(for: language),
                                exactLanguageRecording: voice.sampleIsInLanguage(language),
                                recordedIdentity: "library:" + voice.id)

                            if let description = voice.description, !description.isEmpty {
                                Text(description).font(.footnote).foregroundStyle(.secondary).lineLimit(3)
                            }
                            Button {
                                preview.stop(); importing = voice.id; status = ""
                                let targetLanguage = language
                                Task { @MainActor in
                                    defer { importing = nil }
                                    do { try await model.importElevenVoice(voice, for: targetLanguage); status = "\(voice.name) выбран для языка \(targetLanguage.uppercased())." }
                                    catch { status = error.localizedDescription }
                                }
                            } label: {
                                HStack { Text(importing == voice.id ? "Добавляю…" : "Добавить и выбрать"); Spacer(); Image(systemName: "plus") }
                                    .font(.footnote).padding(.vertical, 5)
                            }.disabled(importing != nil || busy || preview.isLoading)
                        }.padding(18).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 21))
                            .overlay { RoundedRectangle(cornerRadius: 21).strokeBorder(.white.opacity(0.07), lineWidth: 0.6) }
                    }
                    if hasMore { Button(busy ? "Загружаю…" : "Показать ещё") { load(more: true) }.disabled(busy).frame(maxWidth: .infinity).padding() }
                    Text("Генерация общей библиотечной пробы может требовать добавления голоса в аккаунт или подходящего тарифа. Добавление — отдельная кнопка; ей нужно Voices → Write. Платная проба требует Text to Speech.").font(.caption).foregroundStyle(.secondary)
                }.padding(20)
            }.background(Color(red: 0.035, green: 0.039, blue: 0.047))
                .navigationTitle("Голоса").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
                .task {
                    let requestedLanguage = initialLanguage ?? model.partner.rawValue
                    if language != requestedLanguage { language = requestedLanguage }
                    else { refresh() }
                }
                .onChange(of: language) { _, _ in refresh() }
                .onChange(of: scenePhase) { _, phase in if phase != .active { preview.stop() } }
                .onDisappear { preview.stop(); requestID = UUID() }
        }.tint(.white).preferredColorScheme(.dark)
    }
    private func refresh() { preview.stop(); voices = []; page = 0; hasMore = false; load(more: false) }
    private func load(more: Bool) {
        let token = UUID(); requestID = token
        let requestedPage = more ? page + 1 : 0
        let requestedLanguage = language; let query = search
        busy = true; status = ""
        Task { @MainActor in
            do {
                let result = try await model.browseElevenLibrary(language: requestedLanguage, search: query, page: requestedPage)
                guard requestID == token else { return }
                if more { voices.append(contentsOf: result.voices.filter { item in !voices.contains(where: { $0.id == item.id }) }) }
                else { voices = result.voices }
                page = requestedPage; hasMore = result.hasMore; busy = false
            } catch {
                guard requestID == token else { return }
                status = error.localizedDescription; busy = false
            }
        }
    }
}

struct LabAppleVoicePicker: View {
    let title: String
    let language: String
    let voices: [AVSpeechSynthesisVoice]
    @Binding var selection: String
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var preview = LabVoicePreview()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Прослушай любой голос, затем нажми «Выбрать».").font(.footnote).foregroundStyle(.secondary)
                Button { preview.stop(); selection = "" } label: {
                    HStack { Text("Системный голос"); Spacer(); if selection.isEmpty { Image(systemName: "checkmark") } }
                }.padding(17)
                ForEach(voices, id: \.identifier) { voice in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(voice.name).font(.headline)
                                Text(voice.language).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                if preview.activeID == "apple:" + voice.identifier { preview.stop() }
                                else { preview.playApple(voiceID: voice.identifier, language: language) }
                            } label: { Image(systemName: preview.activeID == "apple:" + voice.identifier ? "stop.circle" : "play.circle").font(.system(size: 30, weight: .ultraLight)) }
                                .accessibilityLabel("Прослушать \(voice.name)")
                        }
                        Button { preview.stop(); selection = voice.identifier } label: {
                            HStack { Text(selection == voice.identifier ? "Выбран" : "Выбрать"); Spacer(); if selection == voice.identifier { Image(systemName: "checkmark") } }
                                .font(.footnote)
                        }
                    }.padding(18).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 20))
                }
                if voices.isEmpty { Text("Для этого языка нет установленных голосов. Добавь голос в настройках iPhone.").font(.footnote).foregroundStyle(.secondary) }
                if let error = preview.errorMessage { Text(error).font(.footnote).foregroundStyle(.orange) }
            }.padding(20)
        }.background(Color(red: 0.035, green: 0.039, blue: 0.047)).navigationTitle(title)
            .onDisappear { preview.stop() }
            .onChange(of: scenePhase) { _, phase in if phase != .active { preview.stop() } }
    }
}
