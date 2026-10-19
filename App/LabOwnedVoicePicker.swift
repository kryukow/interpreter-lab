import SwiftUI

struct LabOwnedVoicePicker: View {
    let title: String
    let language: String
    let voices: [LabElevenVoice]
    @Binding var selection: String
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var preview = LabVoicePreview()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Твои голоса ElevenLabs. Прослушай готовое демо, затем выбери голос для перевода.")
                    .font(.footnote).foregroundStyle(.secondary)
                ForEach(voices) { voice in
                    VStack(alignment: .leading, spacing: 13) {
                        HStack {
                            Text(voice.name).font(.headline)
                            Spacer()
                            let identity = "eleven:" + voice.voiceID
                            Button {
                                if preview.activeID == identity { preview.stop() }
                                else { preview.playRecorded(url: voice.preview(for: language), id: identity) }
                            } label: {
                                if preview.isLoading && preview.activeID == identity { ProgressView() }
                                else { Image(systemName: preview.activeID == identity ? "stop.circle" : "play.circle").font(.system(size: 30, weight: .ultraLight)) }
                            }.accessibilityLabel("Прослушать \(voice.name)")
                        }
                        if !voice.sampleIsInLanguage(language) {
                            Text("Демо может звучать на другом языке").font(.caption2).foregroundStyle(.secondary)
                        }
                        Button { preview.stop(); selection = voice.voiceID } label: {
                            HStack { Text(selection == voice.voiceID ? "Выбран" : "Выбрать"); Spacer(); if selection == voice.voiceID { Image(systemName: "checkmark") } }.font(.footnote)
                        }
                    }.padding(18).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 20))
                }
                if let error = preview.errorMessage { Text(error).font(.footnote).foregroundStyle(.orange) }
            }.padding(20)
        }.background(Color(red: 0.035, green: 0.039, blue: 0.047)).navigationTitle(title)
            .onDisappear { preview.stop() }
            .onChange(of: scenePhase) { _, phase in if phase != .active { preview.stop() } }
    }
}
