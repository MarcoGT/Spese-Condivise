import SwiftUI

struct SheetAppearanceView: View {

    let sheet: SharedSheet
    var onSave: (String?, Color) -> Void = { _, _ in }
    @Environment(\.dismiss) private var dismiss
    private let store = SheetAppearanceStore.shared

    @State private var emojiInput: String = ""
    @State private var selectedColorName: String = "blue"

    private var selectedColor: Color {
        SheetAppearanceStore.availableColors.first(where: { $0.name == selectedColorName })?.color ?? .blue
    }

    var body: some View {
        NavigationStack {
            Form {
                // Anteprima
                Section {
                    HStack {
                        Spacer()
                        ZStack {
                            Circle()
                                .fill(selectedColor.opacity(0.2))
                                .frame(width: 72, height: 72)
                            if emojiInput.isEmpty {
                                Image(systemName: "equal")
                                    .font(.system(size: 28, weight: .semibold))
                                    .foregroundColor(selectedColor)
                            } else {
                                Text(String(emojiInput.prefix(1)))
                                    .font(.system(size: 32))
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

                // Emoji
                Section(header: Text(NSLocalizedString("appearance_emoji", comment: ""))) {
                    HStack {
                        TextField(NSLocalizedString("appearance_emoji_placeholder", comment: ""), text: $emojiInput)
                            .font(.title2)
                            .onChange(of: emojiInput) { newValue in
                                if newValue.count > 1 {
                                    emojiInput = String(newValue.prefix(1))
                                }
                            }
                        if !emojiInput.isEmpty {
                            Button {
                                emojiInput = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Colore
                Section(header: Text(NSLocalizedString("appearance_color", comment: ""))) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 16) {
                        ForEach(SheetAppearanceStore.availableColors, id: \.name) { entry in
                            Button {
                                selectedColorName = entry.name
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(entry.color)
                                        .frame(width: 40, height: 40)
                                    if selectedColorName == entry.name {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle(NSLocalizedString("appearance_title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("cancel", comment: "")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("save", comment: "")) {
                        let emoji = emojiInput.isEmpty ? nil : emojiInput
                        store.setEmoji(emoji, for: sheet)
                        store.setColor(named: selectedColorName, for: sheet)
                        onSave(emoji, selectedColor)   // aggiorna @State del parent immediatamente
                        dismiss()
                    }
                }
            }
            .onAppear {
                emojiInput = store.emoji(for: sheet) ?? ""
                // Trova il nome del colore corrente
                let currentColor = store.color(for: sheet)
                selectedColorName = SheetAppearanceStore.availableColors
                    .first(where: { $0.color == currentColor })?.name ?? "blue"
            }
        }
    }
}
