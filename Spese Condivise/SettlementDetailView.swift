import SwiftUI

struct SettlementDetailView: View {

    let settlement: Settlement

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            List {
                // Snapshot saldi
                Section {
                    if settlement.balancesArray.isEmpty {
                        Text(NSLocalizedString("settlement_no_balances", comment: ""))
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(settlement.balancesArray) { balance in
                            HStack {
                                Text(balance.personName ?? "—")
                                    .fontWeight(.medium)
                                Spacer()
                                let val = balance.amount
                                Text(balanceText(val))
                                    .fontWeight(.semibold)
                                    .foregroundColor(balanceColor(val))
                            }
                        }
                    }
                } header: {
                    SectionLabel(title: NSLocalizedString("settlement_balances_at_close", comment: ""))
                }

                // Spese del periodo
                Section {
                    if settlement.expensesArray.isEmpty {
                        Text(NSLocalizedString("settlement_no_expenses", comment: ""))
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(settlement.expensesArray) { expense in
                            ExpenseRowView(expense: expense)
                                .background(Color(.systemBackground))
                                .cornerRadius(14)
                                .shadow(color: Color.black.opacity(0.07), radius: 10, x: 0, y: 4)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        }
                    }
                } header: {
                    SectionLabel(title: NSLocalizedString("settlement_expenses_of_period", comment: ""))
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle(settlementTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var settlementTitle: String {
        guard let date = settlement.date else {
            return NSLocalizedString("settlement_title_fallback", comment: "")
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func balanceText(_ value: Double) -> String {
        if abs(value) < 0.01 { return NSLocalizedString("In pari", comment: "") }
        return AmountFormatter.format(abs(value))
    }

    private func balanceColor(_ value: Double) -> Color {
        if abs(value) < 0.01 { return .secondary }
        return value > 0 ? .green : .red
    }
}

private struct SectionLabel: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.subheadline)
            .fontWeight(.semibold)
            .textCase(nil)
            .foregroundColor(.secondary)
    }
}
