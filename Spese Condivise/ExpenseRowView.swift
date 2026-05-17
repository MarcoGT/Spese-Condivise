import SwiftUI
import CoreData

struct ExpenseRowView: View {

    @ObservedObject var expense: Expense

    var body: some View {
        HStack(spacing: 14) {

            // LEFT — category icon
            let cat = ExpenseCategory.from(expense.category)
            ZStack {
                Circle()
                    .fill(cat.color.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: cat.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(cat.color)
            }

            // CENTER — title + subtitle
            VStack(alignment: .leading, spacing: 4) {
                Text(expense.note?.isEmpty == false ? expense.note! : cat.localizedName)
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
            Text(expense.amount.amountString)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
        }
    }
}
