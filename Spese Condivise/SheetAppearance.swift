import SwiftUI

/// Personalizzazione locale (emoji + colore) per ogni foglio.
/// Salvato su UserDefaults — non sincronizzato via CloudKit (preferenza del dispositivo).
/// ObservableObject: quando un valore cambia, le view che lo osservano si ridisegnano.
final class SheetAppearanceStore: ObservableObject {

    static let shared = SheetAppearanceStore()
    private init() {}

    // Pubblicare objectWillChange forza il ridisegno di tutte le view che usano @ObservedObject
    func notifyChange() {
        objectWillChange.send()
    }

    // MARK: - Colori disponibili

    static let availableColors: [(name: String, color: Color)] = [
        ("blue",   .blue),
        ("purple", .purple),
        ("pink",   .pink),
        ("red",    .red),
        ("orange", .orange),
        ("yellow", .yellow),
        ("green",  .green),
        ("teal",   .teal),
        ("indigo", .indigo),
        ("gray",   .gray),
    ]

    // MARK: - Emoji

    func emoji(for sheet: SharedSheet) -> String? {
        UserDefaults.standard.string(forKey: emojiKey(sheet))
    }

    func setEmoji(_ emoji: String?, for sheet: SharedSheet) {
        let key = emojiKey(sheet)
        if let emoji, !emoji.isEmpty {
            UserDefaults.standard.set(emoji, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
        notifyChange()
    }

    // MARK: - Colore

    func color(for sheet: SharedSheet) -> Color {
        guard let name = UserDefaults.standard.string(forKey: colorKey(sheet)),
              let entry = Self.availableColors.first(where: { $0.name == name })
        else { return .blue }
        return entry.color
    }

    func setColor(named name: String, for sheet: SharedSheet) {
        UserDefaults.standard.set(name, forKey: colorKey(sheet))
        notifyChange()
    }

    // MARK: - Keys (usa objectID — sempre disponibile, anche se sheet.id è nil)

    private func emojiKey(_ sheet: SharedSheet) -> String {
        "sheetEmoji_\(sheet.objectID.uriRepresentation().absoluteString)"
    }

    private func colorKey(_ sheet: SharedSheet) -> String {
        "sheetColor_\(sheet.objectID.uriRepresentation().absoluteString)"
    }
}
