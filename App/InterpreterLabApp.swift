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
        case .arming: return .input
        case .idle: return .idle
        }
    }

    var body: some View {
      ScrollViewReader { reader in
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
                            .frame(width: 40, height: 40)
                            .background(Color.white.opacity(0.035), in: Circle())
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
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
                    .frame(height: model.phase == .recording ? 132 : 180)
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
                .frame(height: model.phase == .recording ? 132 : 180)
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

                LabPipelineStatus(phase: model.phase)
                    .padding(.vertical, 11)

                LabTranscriptConsole(model: model)
                    .padding(.top, 2)

                Text(model.version).font(.system(size: 9, design: .monospaced)).tracking(1).foregroundStyle(Color(white: 0.28)).padding(.top, 8)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background {
            LinearGradient(colors: [Color(white: 0.035), .black], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
        .tint(.white)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    talk("Русский", language: "ru", target: "→ \(partner.uppercaseName)")
                    talk(partner.buttonName, language: partner.rawValue, target: "→ РУССКИЙ")
                }.frame(height: 108)
                Text("Держи · говори после вибросигнала · отпусти")
                    .font(.system(size: 10)).foregroundStyle(Color(white: 0.44))
            }
            .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 8)
            .background {
                LinearGradient(colors: [Color(white: 0.025).opacity(0.96), .black], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea(edges: .bottom)
                    .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 0.5) }
            }
        }
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
        .onChange(of: model.phase) { _, phase in
            if phase == .recording {
                withAnimation(.easeInOut(duration: 0.3)) {
                    reader.scrollTo("liveTranscript", anchor: .bottom)
                }
            }
        }
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

struct LabLoginBrowser: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
