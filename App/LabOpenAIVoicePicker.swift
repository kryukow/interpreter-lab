import SwiftUI

struct LabOpenAIVoicePicker: View {
    let language: String
    let modelID: String
    @Binding var selection: String
    @StateObject private var preview = LabVoicePreview()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("OPENAI · REALTIME 2.1").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                Text("Marin и Cedar рекомендованы OpenAI для лучшего качества. Голоса многоязычные; проба создаётся на выбранном языке через платный API и сохраняется на iPhone.")
                    .font(.footnote).foregroundStyle(.secondary)
                ForEach(LabOpenAISpeech.voices, id: \.self) { voice in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(voice.capitalized).font(.headline)
                            Spacer()
                            if selection == voice { Image(systemName: "checkmark.circle").foregroundStyle(.secondary) }
                        }
                        LabVoiceAuditionControls(preview: preview, voiceID: voice, language: language,
                            modelID: modelID, recordedURL: nil, exactLanguageRecording: false,
                            recordedIdentity: "openai:" + voice + ":" + language)
                        Button(selection == voice ? "Выбран" : "Выбрать") { preview.stop(); selection = voice }
                            .font(.footnote).disabled(preview.isLoading)
                    }.padding(18).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 20))
                }
            }.padding(20)
        }.background(Color(red: 0.035, green: 0.039, blue: 0.047))
            .navigationTitle("Голос OpenAI · \(language.uppercased())")
            .onDisappear { preview.stop() }
            .onChange(of: scenePhase) { _, phase in if phase != .active { preview.stop() } }
    }
}
