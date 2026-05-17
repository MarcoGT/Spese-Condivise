import SwiftUI
import Charts

struct StatisticsView: View {

    let sheet: SharedSheet
    @Environment(\.dismiss) private var dismiss

    // MARK: - Dati calcolati

    private var expenses: [Expense] { sheet.activeExpensesArray }

    private var totalAmount: Double {
        expenses.reduce(0) { $0 + $1.amount }
    }

    private var avgPerPerson: Double {
        let count = sheet.personsArray.count
        guard count > 0 else { return 0 }
        return totalAmount / Double(count)
    }

    private var mostExpensive: Expense? {
        expenses.max(by: { $0.amount < $1.amount })
    }

    // Spese per categoria, ordinate per importo decrescente
    private var byCategory: [(category: ExpenseCategory, total: Double)] {
        var map: [ExpenseCategory: Double] = [:]
        for e in expenses {
            let cat = ExpenseCategory.from(e.category)
            map[cat, default: 0] += e.amount
        }
        return map
            .map { (category: $0.key, total: $0.value) }
            .sorted { $0.total > $1.total }
    }

    // Spese pagate per persona, ordinate per importo decrescente
    private var byPerson: [(name: String, total: Double)] {
        var map: [String: Double] = [:]
        for e in expenses {
            let name = e.paidBy?.name ?? "?"
            map[name, default: 0] += e.amount
        }
        return map
            .map { (name: $0.key, total: $0.value) }
            .sorted { $0.total > $1.total }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {

                    // ── Riepilogo ──
                    summaryCards

                    // ── Torta categorie ──
                    if !byCategory.isEmpty {
                        chartCard(title: NSLocalizedString("stats_by_category", comment: "")) {
                            categoryChart
                        }
                    }

                    // ── Barre per persona ──
                    if !byPerson.isEmpty {
                        chartCard(title: NSLocalizedString("stats_by_person", comment: "")) {
                            personChart
                        }
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(NSLocalizedString("stats_title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("close", comment: "")) { dismiss() }
                }
            }
        }
    }

    // MARK: - Riepilogo cards

    private var summaryCards: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            summaryCard(
                icon: "eurosign.circle.fill",
                color: .blue,
                label: NSLocalizedString("stats_total", comment: ""),
                value: AmountFormatter.format(totalAmount)
            )
            summaryCard(
                icon: "person.2.fill",
                color: .purple,
                label: NSLocalizedString("stats_avg_per_person", comment: ""),
                value: AmountFormatter.format(avgPerPerson)
            )
            summaryCard(
                icon: "list.number",
                color: .orange,
                label: NSLocalizedString("stats_expense_count", comment: ""),
                value: "\(expenses.count)"
            )
            summaryCard(
                icon: "arrow.up.circle.fill",
                color: .red,
                label: NSLocalizedString("stats_most_expensive", comment: ""),
                value: mostExpensive.map { AmountFormatter.format($0.amount) } ?? "—"
            )
        }
    }

    private func summaryCard(icon: String, color: Color, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(color)
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundColor(.primary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
    }

    // MARK: - Barre per categoria (iOS 16 compatible)

    private var categoryChart: some View {
        VStack(spacing: 10) {
            ForEach(byCategory, id: \.category) { item in
                let pct = totalAmount > 0 ? item.total / totalAmount : 0
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: item.category.icon)
                            .font(.caption)
                            .foregroundColor(item.category.color)
                        Text(item.category.localizedName)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        Spacer()
                        Text(AmountFormatter.format(item.total))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                        Text(String(format: "%.0f%%", pct * 100))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 34, alignment: .trailing)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(item.category.color.opacity(0.15))
                            RoundedRectangle(cornerRadius: 4)
                                .fill(item.category.color)
                                .frame(width: geo.size.width * pct)
                        }
                    }
                    .frame(height: 8)
                }
            }
        }
    }

    // MARK: - Barre per persona

    private var personChart: some View {
        Chart(byPerson, id: \.name) { item in
            BarMark(
                x: .value("amount", item.total),
                y: .value("person", item.name)
            )
            .foregroundStyle(Color.accentColor.gradient)
            .cornerRadius(6)
            .annotation(position: .trailing) {
                Text(AmountFormatter.format(item.total))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .chartXAxis(.hidden)
        .frame(height: max(CGFloat(byPerson.count) * 52, 80))
    }

    // MARK: - Wrapper card

    private func chartCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
            content()
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
    }
}
