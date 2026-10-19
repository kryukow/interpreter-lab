import SwiftUI

struct LabSettingsCard<Content: View>: View {
    let title: String
    let symbol: String
    let summary: String
    @State private var expanded: Bool
    private let content: Content

    init(title: String, symbol: String, summary: String, initiallyExpanded: Bool = false,
         @ViewBuilder content: () -> Content) {
        self.title = title; self.symbol = symbol; self.summary = summary
        _expanded = State(initialValue: initiallyExpanded)
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.28)) { expanded.toggle() }
            } label: {
                HStack(alignment: .center, spacing: 13) {
                    Image(systemName: symbol).font(.system(size: 18, weight: .light))
                        .foregroundStyle(.white.opacity(0.7)).frame(width: 25)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(title).font(.system(size: 15, weight: .medium)).foregroundStyle(.white.opacity(0.9))
                        Text(summary).font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color(red: 0.57, green: 0.60, blue: 0.65)).lineLimit(3)
                    }
                    Spacer(minLength: 5)
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4)).rotationEffect(.degrees(expanded ? 180 : 0))
                }.padding(18).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityHint(expanded ? "Свернуть настройки" : "Развернуть настройки")
            if expanded {
                Rectangle().fill(.white.opacity(0.07)).frame(height: 1).padding(.horizontal, 18)
                VStack(alignment: .leading, spacing: 17) { content }
                    .font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18).transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 20).fill(
                LinearGradient(colors: [Color(red: 0.10, green: 0.114, blue: 0.133), Color(red: 0.063, green: 0.071, blue: 0.086)], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(Color(red: 0.19, green: 0.21, blue: 0.235), lineWidth: 0.7) }
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}
