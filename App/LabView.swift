import SwiftUI
import UIKit

struct LabView: View {
    @StateObject private var model = LabSession()
    @State private var settings = false
    @State private var languagePicker = false
    @AppStorage("lab.keepAwake") private var keepAwake = true
    @AppStorage("lab.partnerLanguage") private var partnerCode = "de"
    @Environment(\.scenePhase) private var scenePhase

    private var partner: PartnerLanguage { PartnerLanguage.current(partnerCode) }
    private var canChangeLanguage: Bool { model.phase == .idle && model.held == nil }
    private var canOpenSettings: Bool { model.held == nil && (model.phase == .idle || model.phase == .playing) }
    private var resonancePhase: LabResonancePhase {
        switch model.phase {
        case .arming, .recording: return .input
        case .recognizing, .translating, .preparingVoice: return .processing
        case .playing: return .output
        case .idle: return .idle
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { reader in
                ScrollView {
                    VStack(spacing: 12) {
                        header.padding(.top, 10)
                        LabGraphiteSignalView(signal: model.visualSignal,
                                              phase: resonancePhase, orbitActive: false)
                            .frame(height: min(235, max(150, geometry.size.height * 0.29)))
                            .accessibilityHidden(true)
                        status
                        LabPipelineStatus(phase: model.phase).padding(.vertical, 8)
                        LabTranscriptConsole(model: model)
                        Text(model.version)
                            .font(.system(size: 9, design: .monospaced)).tracking(1)
                            .foregroundStyle(Color(white: 0.3)).padding(.top, 6)
                    }
                    .padding(.horizontal, 18).padding(.bottom, 16)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .safeAreaInset(edge: .bottom, spacing: 0) { recordingDock }
                .onChange(of: model.phase) { _, phase in
                    if phase == .recording {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            reader.scrollTo("liveTranscript", anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background {
            LinearGradient(colors: [Color(white: 0.035), .black], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
        .tint(.white)
        .sheet(isPresented: $settings) { LabSettings(model: model) }
        .sheet(isPresented: $languagePicker) {
            LabGraphiteSelectionSheet(
                title: "Язык собеседника",
                selection: Binding(get: { partnerCode }, set: { value in
                    guard canChangeLanguage else { return }
                    partnerCode = value
                    model.setPartner(PartnerLanguage.current(value))
                }),
                choices: PartnerLanguage.allCases.map {
                    LabGraphiteChoice(id: $0.rawValue, title: $0.name, detail: $0.rawValue.uppercased())
                })
        }
        .onAppear { model.setPartner(partner); updateAwake() }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false; model.stopAll() }
        .onChange(of: partnerCode) { _, value in model.setPartner(PartnerLanguage.current(value)) }
        .onChange(of: keepAwake) { _, _ in updateAwake() }
        .onChange(of: scenePhase) { _, phase in
            updateAwake()
            if phase != .active { model.stopAll() }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 9) {
                Text("INTERPRETER LAB").font(.system(size: 10, weight: .medium))
                    .tracking(3.2).foregroundStyle(Color(white: 0.52))
                Button { languagePicker = true } label: {
                    HStack(spacing: 11) {
                        Text(partner.name).font(.system(size: 26, weight: .medium))
                            .lineLimit(1).minimumScaleFactor(0.8)
                        Image(systemName: "chevron.down").font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color(white: 0.5))
                    }.frame(minHeight: 38, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain).disabled(!canChangeLanguage)
                .accessibilityLabel("Язык собеседника: \(partner.name)")
                .accessibilityHint("Выбрать другой язык")
            }
            Spacer(minLength: 12)
            Button { model.stopAll(); settings = true } label: {
                Image(systemName: "slider.horizontal.3").font(.system(size: 18, weight: .regular))
                    .frame(width: 42, height: 42)
                    .background(Color.white.opacity(0.035), in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5))
            }.disabled(!canOpenSettings).accessibilityLabel("Настройки")
        }
        .sensoryFeedback(.selection, trigger: partnerCode)
    }

    private var status: some View {
        VStack(spacing: 5) {
            Text(model.message).font(.system(size: 14, weight: .medium))
                .multilineTextAlignment(.center).lineLimit(3)
            if model.phase == .recording {
                Text(String(format: "● %.1f с", model.elapsed))
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(Color(white: 0.58))
            }
            if model.phase == .recognizing || model.phase == .translating || model.phase == .preparingVoice || model.phase == .playing {
                Button("Остановить") { model.stopAll() }.font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.58)).frame(minHeight: 30)
            }
        }.frame(minHeight: 28)
    }

    private var recordingDock: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                talk("Русский", language: "ru")
                talk(partner.buttonName, language: partner.rawValue)
            }.frame(height: 76)
            Text("Держи · говори после вибросигнала · отпусти")
                .font(.system(size: 10)).foregroundStyle(Color(white: 0.44))
        }
        .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 8)
        .background {
            LinearGradient(colors: [Color(white: 0.025).opacity(0.97), .black], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 0.5) }
        }
    }

    private func talk(_ title: String, language: String) -> some View {
        PressButton(title: title, subtitle: "", pressed: model.held == language,
                    enabled: !model.busy || model.held == language,
                    begin: { model.begin(language) }, end: { model.end(language) },
                    cancel: { model.abort(language) })
            .frame(maxWidth: .infinity)
    }

    private func updateAwake() {
        UIApplication.shared.isIdleTimerDisabled = keepAwake && scenePhase == .active
    }
}
