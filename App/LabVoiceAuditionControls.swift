import SwiftUI

/// A provider recording and an explicitly billed language sample are separate actions.
struct LabVoiceAuditionControls: View {
    @ObservedObject var preview: LabVoicePreview
    let voiceID: String
    let language: String
    let modelID: String
    let recordedURL: URL?
    let exactLanguageRecording: Bool
    let recordedIdentity: String
    @State private var attemptedHere = false

    private var generatedIdentity: String { "generated:" + voiceID + ":" + language + ":" + modelID }
    private var cached: Bool { preview.hasGenerated(voiceID: voiceID, language: language, modelID: modelID) }
    private var activeHere: Bool { preview.activeID == generatedIdentity || preview.activeID == recordedIdentity }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if exactLanguageRecording && recordedURL != nil {
                recordedButton(title: "Прослушать демо · \(language.uppercased()) · бесплатно")
            } else {
                Text("Нет готового демо на языке \(language.uppercased())")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                if recordedURL != nil {
                    recordedButton(title: "Исходное демо · язык не подтверждён · бесплатно")
                }
                Text("«\(LabVoicePreview.sampleText(for: language))»")
                    .font(.system(size: 11)).lineSpacing(4).foregroundStyle(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(modelID == LabElevenModels.fast ? "Flash v2.5" : modelID == LabElevenModels.natural ? "Multilingual v2" : modelID) · \(cached ? "сохранённое аудио" : "генерация расходует кредиты ElevenLabs")")
                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                Button {
                    attemptedHere = true
                    preview.playGenerated(voiceID: voiceID, language: language, modelID: modelID)
                } label: {
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: cached ? "play.circle" : "waveform.badge.plus")
                            .font(.system(size: 18, weight: .light))
                        Text(cached ? "Прослушать сохранённую пробу · без новых кредитов" : "Создать пробу · \(language.uppercased()) · расход кредитов")
                            .font(.system(size: 11, weight: .medium)).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }.frame(minHeight: 44).padding(.horizontal, 12)
                        .background(.white.opacity(cached ? 0.035 : 0.065), in: RoundedRectangle(cornerRadius: 12))
                        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(cached ? 0.07 : 0.15), lineWidth: 0.7) }
                }.buttonStyle(.plain).disabled(preview.isLoading)
            }
            if activeHere {
                HStack(spacing: 9) {
                    if preview.isLoading { ProgressView().controlSize(.mini) }
                    Text(preview.isLoading ? "Готовлю пробу…" : "Проба воспроизводится")
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Button("Стоп") { preview.stop() }.font(.caption)
                }.padding(.vertical, 4)
            }
            if attemptedHere, let error = preview.errorMessage {
                Text(error).font(.footnote).foregroundStyle(.orange)
            }
        }
        .onChange(of: preview.activeID) { _, identity in
            if let identity, identity != generatedIdentity && identity != recordedIdentity { attemptedHere = false }
        }
    }

    private func recordedButton(title: String) -> some View {
        Button {
            attemptedHere = true
            preview.playRecorded(url: recordedURL, id: recordedIdentity)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "play.circle").font(.system(size: 19, weight: .light))
                Text(title).font(.system(size: 11)).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }.frame(minHeight: 44).padding(.horizontal, 12)
                .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).disabled(preview.isLoading)
    }
}
