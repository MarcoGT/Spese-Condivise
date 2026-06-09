import SwiftUI

/// Riga del foglio nella lista principale.
/// Riceve emoji e colore già risolti dal parent — nessuna logica di store qui.
struct SheetRowView: View {

    let sheet: SharedSheet
    let emoji: String?
    let sheetColor: Color
    let balanceText: String
    let balanceColor: Color
    let lastSeenRefresh: Date

    private var iconName: String {
        balanceColor == .green ? "arrow.up"
            : balanceColor == .red ? "arrow.down"
            : "equal"
    }

    var body: some View {
        HStack(spacing: 14) {

            // Cerchio: emoji personalizzata o indicatore bilancio
            ZStack {
                Circle()
                    .fill((emoji != nil ? sheetColor : balanceColor).opacity(0.15))
                    .frame(width: 44, height: 44)
                if let e = emoji {
                    Text(e)
                        .font(.system(size: 22))
                } else {
                    Image(systemName: iconName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(balanceColor)
                }
            }

            // Nome + pallino nuove spese
            HStack(spacing: 6) {
                Text(sheet.name ?? NSLocalizedString("sheet", comment: ""))
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                if LastSeenStore.newExpensesCount(for: sheet) > 0 {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 8, height: 8)
                }
            }

            Spacer()

            Text(balanceText)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(balanceColor)
                .lineLimit(1)
        }
        .padding(.vertical, 14)
        .padding(.leading, 20)
        .padding(.trailing, 16)
        .background(
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.systemBackground))
                    .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
                // Bordo sinistro colorato
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(balanceColor.opacity(0.7))
                    .frame(width: 4)
                    .padding(.vertical, 10)
                    .padding(.leading, 0)
            }
        )
    }
}
