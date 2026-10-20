import SwiftUI

struct LabOpenAISpeechSettings: View {
    @ObservedObject var model: LabSession
    var body: some View {
        LabSettingsCard(title: "Студия OpenAI", symbol: "waveform", summary: "\(model.openAISpeechModel == LabOpenAISpeech.model ? "Realtime 2.1" : "Realtime 2.1 Mini") · \(model.keySaved ? "ключ сохранён" : "нужен API-ключ")\n\(model.openAISpeechAutoGenerate ? "Автогенерация · расход API" : "Генерация вручную")") {
            Text("Озвучивает готовый перевод. В OpenAI отправляется только текст; микрофон распознаёт Apple. Голос создан ИИ.")
                .font(.footnote).foregroundStyle(.secondary)
            LabGraphiteSelectionField(title: "Модель озвучивания", selection: $model.openAISpeechModel, choices: [
                LabGraphiteChoice(id: LabOpenAISpeech.model, title: "GPT-Realtime 2.1", detail: "Полная модель · основной вариант", symbol: "waveform"),
                LabGraphiteChoice(id: LabOpenAISpeech.mini, title: "GPT-Realtime 2.1 Mini", detail: "Экономичный вариант", symbol: "bolt")
            ], note: "Оплачивается отдельно через OpenAI API. Подписка ChatGPT не включает эти запросы.")
            NavigationLink {
                LabOpenAIVoicePicker(language: "ru", modelID: model.openAISpeechModel, selection: $model.openAIRussianVoice)
            } label: { row("Русский голос", model.openAIRussianVoice) }
            NavigationLink {
                LabOpenAIVoicePicker(language: model.partner.rawValue, modelID: model.openAISpeechModel, selection: $model.openAIPartnerVoice)
            } label: { row(model.partner.name, model.openAIPartnerVoice) }
            Toggle("Автогенерация OpenAI · расход API", isOn: $model.openAISpeechAutoGenerate)
            Text(model.openAISpeechAutoGenerate
                 ? "Если автоматическое озвучивание включено выше, после перевода создаётся платное аудио."
                 : "По умолчанию платная генерация вручную: нажми «Озвучить OpenAI» под переводом. Пробы голосов оплачиваются отдельно по явной кнопке.")
                .font(.footnote).foregroundStyle(.secondary)
            Text("Marin и Cedar рекомендованы OpenAI для лучшего качества. Доступ к модели зависит от API-проекта. При ошибке используется резервный Apple TTS с сообщением о причине.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
    private func row(_ title: String, _ voice: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) { Text(title); Text(voice.capitalized).font(.caption).foregroundStyle(.secondary) }
            Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }
}
