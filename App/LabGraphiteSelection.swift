import SwiftUI

struct LabGraphiteChoice: Identifiable, Equatable {
    let id: String
    let title: String
    var detail: String = ""
    var symbol: String = ""
}

/// The same deliberate selection surface is used for routing, models and languages.
/// Opening it has no side effects; only tapping a row writes the binding.
struct LabGraphiteSelectionField: View {
    let title: String
    @Binding var selection: String
    let choices: [LabGraphiteChoice]
    var note: String = ""
    @State private var presented = false

    private var current: LabGraphiteChoice? { choices.first { $0.id == selection } }
    var body: some View {
        Button { presented = true } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title.uppercased()).font(.system(size: 9, weight: .medium, design: .monospaced))
                        .tracking(1.6).foregroundStyle(Color(white: 0.49))
                    Text(current?.title ?? (selection.isEmpty ? "Выбрать" : selection))
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(Color(white: 0.88))
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .medium)).foregroundStyle(Color(white: 0.47))
            }.padding(15).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(white: 0.045), in: RoundedRectangle(cornerRadius: 15))
                .overlay { RoundedRectangle(cornerRadius: 15).strokeBorder(Color.white.opacity(0.075), lineWidth: 0.7) }
        }.buttonStyle(.plain)
            .accessibilityLabel(title).accessibilityValue(current?.title ?? selection)
            .sheet(isPresented: $presented) {
                LabGraphiteSelectionSheet(title: title, selection: $selection, choices: choices, note: note)
            }
    }
}

struct LabGraphiteSelectionSheet: View {
    let title: String
    @Binding var selection: String
    let choices: [LabGraphiteChoice]
    var note: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("INTERPRETER LAB").font(.system(size: 9, design: .monospaced)).tracking(2.5)
                            .foregroundStyle(Color(white: 0.43))
                        Text(title).font(.system(size: 23, weight: .medium)).tracking(-0.5)
                    }
                    Spacer(minLength: 8)
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(white: 0.64)).frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.035), in: Circle())
                            .overlay { Circle().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.7) }
                    }.buttonStyle(.plain).accessibilityLabel("Закрыть")
                }.padding(.bottom, 10)
                ForEach(choices) { choice in
                    choiceRow(choice)
                }
                if choices.isEmpty {
                    Text("Список пока пуст. Обнови доступные модели в настройках подключения.")
                        .font(.footnote).foregroundStyle(Color(white: 0.6)).padding(.vertical, 20)
                }
                if !note.isEmpty {
                    Text(note).font(.system(size: 11, design: .monospaced)).lineSpacing(5)
                        .foregroundStyle(Color(white: 0.47)).padding(.top, 10)
                }
            }.padding(.horizontal, 22).padding(.top, 30).padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .background {
            LinearGradient(colors: [Color(red: 0.082, green: 0.094, blue: 0.110), Color(red: 0.035, green: 0.043, blue: 0.051)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
        }
        .presentationDetents(choices.count > 5 ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .preferredColorScheme(.dark)
    }

    private func choiceRow(_ choice: LabGraphiteChoice) -> some View {
        let selected = selection == choice.id
        return Button {
            selection = choice.id
            dismiss()
        } label: {
            HStack(spacing: 13) {
                if !choice.symbol.isEmpty {
                    Image(systemName: choice.symbol).font(.system(size: 18, weight: .light))
                        .foregroundStyle(Color(white: 0.66)).frame(width: 23)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(choice.title).font(.system(size: 15, weight: .medium)).foregroundStyle(Color(white: 0.9))
                    if !choice.detail.isEmpty { Text(choice.detail).font(.system(size: 11)).foregroundStyle(Color(white: 0.63)).lineSpacing(3) }
                }.multilineTextAlignment(.leading)
                Spacer(minLength: 6)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .light)).foregroundStyle(Color(white: selected ? 0.82 : 0.3))
            }.padding(16).frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 17).fill(
                        LinearGradient(colors: selected ? [Color(red: 0.16, green: 0.19, blue: 0.23), Color(red: 0.09, green: 0.115, blue: 0.15)] : [Color(white: 0.067), Color(white: 0.05)], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                .overlay { RoundedRectangle(cornerRadius: 17).strokeBorder(Color.white.opacity(selected ? 0.32 : 0.08), lineWidth: 0.8) }
        }.buttonStyle(.plain)
            .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
