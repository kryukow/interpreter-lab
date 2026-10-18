import SwiftUI
import UIKit

@main
struct InterpreterLabApp: App {
    var body: some Scene {
        WindowGroup { LabView().preferredColorScheme(.dark) }
    }
}

struct LabView: View {
    @StateObject private var model = LabSession()
    @State private var settings = false
    @AppStorage("lab.keepAwake") private var keepAwake = true
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("INTERPRETER LAB").font(.caption2).tracking(3).foregroundStyle(.secondary)
                    Text("Русский ↔ Deutsch").font(.title2.bold())
                }
                Spacer()
                Button {
                    model.stopAll()
                    settings = true
                } label: {
                    Image(systemName: "gearshape.fill").font(.title2)
                }
                .accessibilityLabel("Настройки")
            }

            Image(systemName: "infinity").font(.system(size: 52, weight: .light))
            HStack(spacing: 4) {
                ForEach(0..<40, id: \.self) { index in
                    Capsule().fill(.white.opacity(0.85))
                        .frame(width: 3, height: model.phase == .recording ? max(3, model.levels[index] * 42) : 3)
                }
            }.frame(height: 44).accessibilityHidden(true)

            VStack(spacing: 5) {
                Text(model.message).font(.headline).multilineTextAlignment(.center)
                if model.phase == .recording {
                    Text(String(format: "● %.1f с", model.elapsed)).font(.caption.monospacedDigit())
                }
                if model.busy && model.phase != .recording && model.phase != .arming {
                    Button("Остановить") { model.stopAll() }
                        .font(.caption).foregroundStyle(.white.opacity(0.85))
                }
            }.frame(minHeight: 56)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("РАСПОЗНАВАНИЕ").font(.caption2).foregroundStyle(.secondary)
                    Text("Apple Speech").font(.subheadline.bold())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("ОЗВУЧИВАНИЕ").font(.caption2).foregroundStyle(.secondary)
                    Text("Apple TTS · локально").font(.subheadline.bold())
                }
            }.padding(16).background(Color(white: 0.07), in: RoundedRectangle(cornerRadius: 22))

            HStack(spacing: 16) {
                talk("Русский", language: "ru", target: "→ DEUTSCH")
                talk("Deutsch", language: "de", target: "→ РУССКИЙ")
            }.frame(height: 145)

            Text("Держи → вибросигнал → говори → отпусти")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("ГОЛОСОВОЙ ПЕРЕВОД · LAB")
                        .font(.caption).foregroundStyle(.secondary)

                    Text("РАСПОЗНАНО · \(model.language == "ru" ? "РУССКИЙ" : "DEUTSCH")")
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

                    Button("Прослушать снова · бесплатно") { model.replay() }
                        .disabled(!model.canReplay)
                    if !model.detail.isEmpty {
                        Text(model.detail).font(.caption2).foregroundStyle(.secondary)
                    }
                    Text("В Lab запись заканчивается по отпусканию кнопки. OpenAI получает только распознанный текст, а встроенный голос Apple озвучивает окончательный перевод.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(18)
                .background(Color(white: 0.055), in: RoundedRectangle(cornerRadius: 22))
            }
            .frame(maxHeight: .infinity)

            Text(model.version).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
        .background(Color.black).tint(.white)
        .sheet(isPresented: $settings) { LabSettings(model: model) }
        .onAppear { updateAwake() }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            model.stopAll()
        }
        .onChange(of: keepAwake) { _, _ in updateAwake() }
        .onChange(of: scenePhase) { _, phase in
            updateAwake()
            if phase != .active { model.stopAll() }
        }
    }

    private func talk(_ title: String, language: String, target: String) -> some View {
        LabPressButton(title: title, subtitle: target, pressed: model.held == language,
                       enabled: model.canBegin || model.held == language,
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
    @State private var notice = ""
    @State private var deleteKey = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Экспериментальный режим") {
                    Text("Apple Speech → OpenAI Responses API → AVSpeechSynthesizer")
                    Text("Нет Realtime/WebRTC и потокового звука OpenAI. Русский и немецкий распознаёт Apple; для некоторых языков Apple может использовать сервер.")
                        .font(.footnote)
                }
                Section("API-ключ OpenAI") {
                    Text(model.keySaved ? "Ключ сохранён в Keychain этого приложения" : "Добавь отдельный API-ключ OpenAI")
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
                    Text("Используется отдельный платный API, не подписка ChatGPT Plus. Ключ не включён в исходники.")
                        .font(.footnote)
                }
                Section("Модель перевода") {
                    Picker("Модель", selection: $model.modelID) {
                        Text("GPT-4.1 mini · экономнее").tag("gpt-4.1-mini")
                        Text("GPT-4.1 · качественнее").tag("gpt-4.1")
                    }
                }
                Section("Озвучивание") {
                    Toggle("Автоматически озвучивать перевод", isOn: $model.autoSpeak)
                    Picker("Немецкий голос", selection: $model.germanVoiceID) {
                        Text("Системный по умолчанию").tag("")
                        ForEach(model.voices(for: "de"), id: \.identifier) { voice in
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
                Section("Экран") {
                    Toggle("Не гасить экран", isOn: $keepAwake)
                }
                Section("О приложении") {
                    Text("Экспериментальная сборка. Не влияет на Interpreter Live.")
                    Text(model.version).foregroundStyle(.secondary)
                }
                if !notice.isEmpty {
                    Section { Text(notice).font(.footnote) }
                }
            }
            .navigationTitle("Настройки")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { key = ""; dismiss() }
                }
            }
            .confirmationDialog("Удалить API-ключ из этого приложения?", isPresented: $deleteKey) {
                Button("Удалить", role: .destructive) {
                    do { try model.deleteKey(); notice = "Ключ удалён" }
                    catch { notice = error.localizedDescription }
                }
            }
            .onDisappear { key = "" }
        }
        .tint(.white)
    }
}
