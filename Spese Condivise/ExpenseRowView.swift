import SwiftUI
import CoreData

struct ExpenseRowView: View {

    @ObservedObject var expense: Expense

    var body: some View {
        HStack(spacing: 14) {

            // LEFT — avatar circle
            ZStack {
                Circle()
                    .fill(avatarColor)
                    .frame(width: 44, height: 44)

                if let initial = payerInitial {
                    Text(initial)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                } else {
                    Image(systemName: "questionmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }
            }

            // CENTER — title + subtitle
            VStack(alignment: .leading, spacing: 4) {
                Text(expense.note ?? "Spesa")
                    .font(.headline)

                HStack(spacing: 6) {
                    Text(expense.date ?? Date(), style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let payerName = expense.paidBy?.name {
                        Text("·")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(payerName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // RIGHT — amount
            Text(expenseAmountText)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
        }
    }

    // MARK: - Helpers

    private var expenseAmountText: String {
        String(
            format: NSLocalizedString(
                "expense_amount",
                comment: "expense amount"
            ),
            expense.amount
        )
    }

    private var payerInitial: String? {
        guard let name = expense.paidBy?.name, !name.isEmpty else { return nil }
        return String(name.prefix(1)).uppercased()
    }

    private var avatarColor: Color {
        let palette: [Color] = [.indigo, .teal, .orange, .pink, .purple]
        guard let name = expense.paidBy?.name, !name.isEmpty else {
            return palette[0]
        }
        let index = abs(name.hashValue) % palette.count
        return palette[index]
    }
}
