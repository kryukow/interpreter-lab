import SwiftUI

/// Presentation of a persisted selection does not depend on a network catalog.
struct LabOwnedVoiceSelectionSummary {
    let name: String
    let availableInCatalog: Bool

    init(selection: String, voices: [LabElevenVoice], defaults: UserDefaults = .standard) {
        let voice = voices.first { $0.voiceID == selection }
        let names = defaults.dictionary(forKey: "lab.elevenVoiceNames") as? [String: String] ?? [:]
        name = voice?.name ?? names[selection] ?? "Сохранённый голос"
        availableInCatalog = voice != nil
    }
}

struct LabOwnedVoicePicker: View {
    @ObservedObject var model: LabSession
    let title: String
    let language: String
    @Binding var selection: String
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var preview = LabVoicePreview()
    @State private var loading = false
    @State private var loadError = ""
    @State private var loaded = false
    @State private var showLibrary = false

    private var voices: [LabElevenVoice] { model.elevenVoices }
    private var savedSelection: LabOwnedVoiceSelectionSummary {
        LabOwnedVoiceSelectionSummary(selection: selection, voices: voices)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Твои голоса ElevenLabs. Готовые демо бесплатны. Если записи на нужном языке нет, можно явно создать платную пробу — выбор голоса при этом не изменится.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button { preview.stop(); showLibrary = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "globe")
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Больше голосов · библиотека ElevenLabs").font(.system(size: 12, weight: .medium))
                            Text("Общая библиотека · \(language.uppercased())").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                        }
                        Spacer(); Image(systemName: "chevron.right").font(.caption)
                    }.padding(16).background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16))
                }.buttonStyle(.plain).disabled(preview.isLoading)
                Text("ГОЛОСА АККАУНТА · \(voices.count)")
                    .font(.system(size: 10, design: .monospaced)).tracking(1.2).foregroundStyle(.secondary)
                if !selection.isEmpty {
                    VStack(alignment: .leading, spacing: 9) {
                        Label("ВЫБРАН ДЛЯ \(language.uppercased())", systemImage: "checkmark.circle")
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                        Text(savedSelection.name).font(.headline)
                        if !savedSelection.availableInCatalog {
                            Text(loaded ? "Голос сохранён, но его нет в текущем списке аккаунта. Проверь доступность после обновления списка или выбери другой голос." : "Выбор сохранён на iPhone. Загрузка списка проверит доступность голоса и его демо.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 20))
                }
                Button { Task { await reload() } } label: {
                    HStack {
                        if loading { ProgressView().controlSize(.small) }
                        else { Image(systemName: "arrow.clockwise") }
                        Text(loading ? "Загружаю голоса…" : "Обновить список голосов")
                        Spacer()
                    }.font(.footnote).padding(15)
                        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 15))
                }.disabled(loading)
                if !loadError.isEmpty {
                    Text(loadError).font(.footnote).foregroundStyle(.orange)
                }
                if voices.isEmpty && !loading {
                    Text(loaded ? "В аккаунте пока нет доступных голосов. Добавь голос из библиотеки ElevenLabs, затем обнови список." : "Список голосов ещё не загружен. Сохранённый выбор продолжает отображаться выше.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(voices) { voice in
                    VStack(alignment: .leading, spacing: 13) {
                        HStack {
                            Text(voice.name).font(.headline)
                            Spacer()
                        }
                        LabVoiceAuditionControls(preview: preview, voiceID: voice.voiceID,
                            language: language, modelID: model.elevenModel,
                            recordedURL: voice.preview(for: language),
                            exactLanguageRecording: voice.sampleIsInLanguage(language),
                            recordedIdentity: "eleven:" + voice.voiceID)

                        Button { preview.stop(); selection = voice.voiceID } label: {
                            HStack { Text(selection == voice.voiceID ? "Выбран" : "Выбрать"); Spacer(); if selection == voice.voiceID { Image(systemName: "checkmark") } }.font(.footnote)
                        }.disabled(preview.isLoading)
                    }.padding(18).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 20))
                }
                if let error = preview.errorMessage { Text(error).font(.footnote).foregroundStyle(.orange) }
            }.padding(20)
        }.background(Color(red: 0.035, green: 0.039, blue: 0.047)).navigationTitle(title)
            .task {
                if voices.isEmpty { await reload() }
                else { loaded = true }
            }
            .onDisappear { preview.stop() }
            .onChange(of: scenePhase) { _, phase in if phase != .active { preview.stop() } }
            .sheet(isPresented: $showLibrary) { LabVoiceLibrary(model: model, initialLanguage: language) }
    }

    @MainActor private func reload() async {
        guard !loading else { return }
        loading = true; loadError = ""
        defer { loading = false }
        do {
            try await model.loadElevenVoices()
            loaded = true
        } catch {
            loadError = "Не удалось обновить голоса: \(error.localizedDescription). Для списка нужно разрешение Voices → Read. Сохранённый выбор не изменён."
        }
    }
}
