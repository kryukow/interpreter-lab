import SwiftUI
import UIKit

/// The text shown here is the recognizer's current hypothesis, never a staged
/// typewriter copy. Apple can revise whole words while the user is speaking.
struct LabTranscriptConsole: View {
    @ObservedObject var model: LabSession
    @State private var followTail = true

    private var live: Bool { model.phase == .recording || model.phase == .recognizing }
    private var sourceName: String { model.language == "ru" ? "RU" : model.partner.rawValue.uppercased() }
    private var targetName: String { model.language == "ru" ? model.partner.rawValue.uppercased() : "RU" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "waveform.path")
                Text("ТРАНСКРИПТ").tracking(2)
                Spacer()
                Text(live ? "LIVE" : "\(sourceName) → \(targetName)")
                    .foregroundStyle(live ? Color.white : Color(white: 0.5))
                Circle().fill(Color.white.opacity(live ? 0.9 : 0.22)).frame(width: 4, height: 4)
            }
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(Color(white: 0.55))
            .padding(.horizontal, 16).padding(.vertical, 14)

            Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)

            HStack(alignment: .top, spacing: 8) {
                Text(">").foregroundStyle(Color(white: 0.43))
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                    .padding(.top, 11)
                ZStack(alignment: .topLeading) {
                    LabLiveTextView(text: $model.source, followTail: $followTail,
                                    editable: !model.busy && model.phase != .playing)
                        .frame(height: 132)
                        .id("liveTranscript")
                    if model.source.isEmpty {
                        Text(live ? "Слушаю…" : "Говори или введи текст…")
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundStyle(Color(white: 0.34))
                            .padding(.top, 11)
                            .allowsHitTesting(false)
                    }
                }
            }.padding(.horizontal, 16).padding(.top, 5)

            HStack {
                Text(live ? "Apple Speech · текущие слова" : "\(model.source.count) символов · можно редактировать")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color(white: 0.4))
                Spacer(minLength: 2)
                if !followTail {
                    Button { followTail = true } label: {
                        Label("К текущим словам", systemImage: "arrow.down")
                            .font(.system(size: 10, weight: .medium))
                    }
                }
            }.padding(.horizontal, 16).padding(.bottom, 12)

            Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)

            HStack {
                Text("01 / ИСХОДНЫЙ ТЕКСТ")
                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(Color(white: 0.4))
                Spacer()
                Button { model.translate() } label: {
                    Label("Перевести", systemImage: "arrow.up.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .disabled(model.busy || model.phase == .playing || model.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding(16)

            Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)

            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Text("02 / ПЕРЕВОД · \(targetName)")
                        .font(.system(size: 9, design: .monospaced)).tracking(1)
                    Spacer()
                    if model.phase == .translating { ProgressView().controlSize(.mini) }
                }.foregroundStyle(Color(white: 0.48))
                Text(model.translation.isEmpty ? "Здесь появится перевод" : model.translation)
                    .font(.system(size: 16, weight: .regular))
                    .lineSpacing(5)
                    .foregroundStyle(Color(white: model.translation.isEmpty ? 0.3 : 0.9))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button { model.replay() } label: {
                    Label(model.replayCaption, systemImage: "play.fill")
                        .font(.system(size: 11, weight: .medium))
                        .multilineTextAlignment(.leading)
                }.disabled(!model.canReplay)
                if !model.detail.isEmpty {
                    Text(model.detail).font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Color(white: 0.4)).textSelection(.enabled)
                }
            }.padding(16)
        }
        .background {
            RoundedRectangle(cornerRadius: 23)
                .fill(LinearGradient(colors: [Color(white: 0.075), Color(white: 0.035)], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay { RoundedRectangle(cornerRadius: 23).strokeBorder(Color.white.opacity(0.085), lineWidth: 0.5) }
        .onChange(of: model.phase) { _, phase in if phase == .recording { followTail = true } }
    }
}

struct LabLiveTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var followTail: Bool
    let editable: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.backgroundColor = .clear
        view.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        view.textColor = UIColor(white: 0.83, alpha: 1)
        view.tintColor = .white
        view.textContainerInset = UIEdgeInsets(top: 9, left: 0, bottom: 18, right: 0)
        view.textContainer.lineFragmentPadding = 0
        view.keyboardDismissMode = .interactive
        view.alwaysBounceVertical = true
        view.delegate = context.coordinator
        view.accessibilityLabel = "Распознанный текст"
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        let changed = view.text != text
        let resumed = followTail && !context.coordinator.lastFollow
        context.coordinator.lastFollow = followTail
        if changed {
            let selection = view.selectedRange
            view.text = text
            if view.isFirstResponder { view.selectedRange = NSRange(location: min(selection.location, (text as NSString).length), length: 0) }
        }
        view.isEditable = editable
        if followTail && (changed || resumed) && !view.isFirstResponder {
            // Layout before scrolling is essential for long partial ASR results.
            view.layoutManager.ensureLayout(for: view.textContainer)
            view.layoutIfNeeded()
            view.scrollRangeToVisible(NSRange(location: (text as NSString).length, length: 0))
        }
    }
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: LabLiveTextView
        var lastFollow = true
        init(_ parent: LabLiveTextView) { self.parent = parent }
        func textViewDidChange(_ textView: UITextView) { parent.text = textView.text }
        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { parent.followTail = false }
        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate { resumeIfAtBottom(scrollView) }
        }
        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { resumeIfAtBottom(scrollView) }
        private func resumeIfAtBottom(_ view: UIScrollView) {
            if view.contentOffset.y + view.bounds.height >= view.contentSize.height - 24 { parent.followTail = true }
        }
    }
}

struct LabPipelineStatus: View {
    let phase: LabSession.Phase
    private var active: Int? {
        switch phase {
        case .arming, .recording, .recognizing: return 0
        case .translating: return 1
        case .preparingVoice, .playing: return 2
        case .idle: return nil
        }
    }
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3) { index in
                HStack(spacing: 6) {
                    Circle().fill(Color.white.opacity(active == index ? 0.95 : 0.18)).frame(width: 4, height: 4)
                    Text(["РЕЧЬ", "ПЕРЕВОД", "ГОЛОС"][index])
                        .font(.system(size: 8, weight: active == index ? .semibold : .regular, design: .monospaced))
                        .tracking(1.5)
                        .foregroundStyle(Color(white: active == index ? 0.9 : 0.35))
                }
                if index < 2 { Rectangle().fill(Color.white.opacity(0.1)).frame(maxWidth: 30).frame(height: 0.5) }
            }
        }
        .animation(.easeInOut(duration: 0.4), value: phase)
        .accessibilityElement(children: .combine)
    }
}
