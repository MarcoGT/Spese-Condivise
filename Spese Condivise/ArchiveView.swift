import SwiftUI

struct ArchiveView: View {

    @ObservedObject var sheet: SharedSheet

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            if sheet.settlementsArray.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(sheet.settlementsArray) { settlement in
                        NavigationLink {
                            SettlementDetailView(settlement: settlement)
                        } label: {
                            settlementRow(settlement)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(NSLocalizedString("archive_title", comment: ""))
        .navigationBarTitleDisplayMode(.large)
    }

    @ViewBuilder
    private func settlementRow(_ settlement: Settlement) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: "archivebox.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(formattedDate(settlement.date))
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(String(
                    format: NSLocalizedString("archive_expense_count", comment: ""),
                    settlement.expensesArray.count
                ))
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()

            Text(AmountFormatter.format(settlement.totalExpensesAmount))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
        )
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "archivebox")
                .font(.system(size: 48, weight: .thin))
                .foregroundColor(.secondary)
            Text(NSLocalizedString("archive_empty", comment: ""))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private func formattedDate(_ date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
