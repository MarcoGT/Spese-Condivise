import SwiftUI
import CoreData

struct ExpenseRowView: View {
    
    @ObservedObject var expense: Expense
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                
                Text(expense.note ?? "")
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
                    
                    //let participants = (expense.splitBetween as? Set<Person>) ?? []
                    
                    /*if !participants.isEmpty {
                        Text("·")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(
                            String(
                                format: NSLocalizedString(
                                    "for_people_names",
                                    comment: "for people {names}"
                                ),
                                participants
                                    .compactMap { $0.name }
                                    .sorted()
                                    .joined(separator: ", ")
                            )
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }*/
                }
            }
            
            Spacer()
            
            Text(expenseAmountText)
                .font(.headline)
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
}
