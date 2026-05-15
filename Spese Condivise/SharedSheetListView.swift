import SwiftUI
import CoreData

struct SharedSheetListView: View {

    // MARK: - ENVIRONMENT
    @EnvironmentObject private var currentUser: CurrentUser
    @EnvironmentObject private var syncState: AppSyncState
    @Environment(\.managedObjectContext) private var viewContext

    // MARK: - FETCH
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \SharedSheet.lastUpdated, ascending: false)],
        animation: .default
    )
    private var sheets: FetchedResults<SharedSheet>

    // MARK: - STATE
    @State private var showingAddSheet = false
    @State private var shareAlertMessage = ""
    @State private var showingShareAlert = false
    @State private var shareAlertIsSuccess = false

    private let remoteChangePublisher = NotificationCenter.default
        .publisher(for: .NSPersistentStoreRemoteChange)

    // MARK: - BODY
    var body: some View {
        ZStack {
            NavigationStack {
                ZStack {
                    Color(.systemGroupedBackground).ignoresSafeArea()

                    if sheets.isEmpty {
                        emptyStateView
                    } else {
                        List {
                            // Hero balance card
                            Section {
                                heroBalanceCard
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            }

                            // Section header "I tuoi fogli"
                            Section {
                                ForEach(sheets) { sheet in
                                    NavigationLink {
                                        SheetDetailView(sheet: sheet)
                                    } label: {
                                        sheetRow(sheet)
                                    }
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                                }
                                .onDelete(perform: deleteSheets)
                            } header: {
                                Text(NSLocalizedString("I tuoi fogli", comment: ""))
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                    .textCase(nil)
                                    .listRowBackground(Color.clear)
                                    .padding(.top, 4)
                                    .padding(.bottom, 2)
                            }
                        }
                        .listStyle(.plain)
                        .animation(.spring(response: 0.4), value: sheets.count)
                    }
                }
                .navigationTitle(NSLocalizedString("Shared Expenses", comment: ""))
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        EditButton()
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showingAddSheet = true
                        } label: {
                            Image(systemName: "plus")
                                .fontWeight(.semibold)
                        }
                    }
                }
                .sheet(isPresented: $showingAddSheet) {
                    AddSharedSheetView()
                }
            }

            // OVERLAY SYNC
            if syncState.showOverlay {
                SyncOverlay()
            }
        }
        .onAppear {
            bootstrapCurrentUserIfNeeded()
            AppSyncState.current = syncState

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                if !syncState.initialSyncCompleted {
                    syncState.showOverlay = true
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                syncState.initialSyncCompleted = true
                syncState.showOverlay = false
            }
        }
        .onReceive(remoteChangePublisher) { _ in
            viewContext.refreshAllObjects()
        }
        // Osserva AppSyncState per il risultato dell'accettazione share.
        // .onChange è immune alle race condition tipiche dei publisher Combine:
        // lo stato @Published persiste anche se la view non era ancora attiva.
        .onChange(of: syncState.pendingShareSuccess) { success in
            guard success else { return }
            viewContext.refreshAllObjects()
            shareAlertIsSuccess = true
            shareAlertMessage = NSLocalizedString("share_accepted_message", comment: "Share accepted successfully")
            showingShareAlert = true
            syncState.pendingShareSuccess = false
        }
        .onChange(of: syncState.pendingShareError) { errorMsg in
            guard let msg = errorMsg else { return }
            shareAlertIsSuccess = false
            shareAlertMessage = msg
            showingShareAlert = true
            syncState.pendingShareError = nil
        }
        .alert(shareAlertIsSuccess
               ? NSLocalizedString("share_accepted_title", comment: "Share accepted title")
               : NSLocalizedString("sharing error", comment: "sharing error"),
               isPresented: $showingShareAlert) {
            Button("OK") {}
        } message: {
            Text(shareAlertMessage)
        }
    }

    // MARK: - HERO BALANCE CARD

    @ViewBuilder
    private var heroBalanceCard: some View {
        let balance = totalBalance()
        let isPositive = balance > 0
        let isEven = balance == 0
        let accentColor: Color = isEven ? .secondary : (isPositive ? .green : .red)

        VStack(spacing: 6) {
            Text(NSLocalizedString("Saldo totale", comment: ""))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fontWeight(.medium)

            Text(totalBalanceAmountText())
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundColor(accentColor)
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            if !isEven {
                Text(isPositive
                     ? NSLocalizedString("ti devono", comment: "")
                     : NSLocalizedString("devi pagare", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text(NSLocalizedString("balance_even", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
        )
    }

    // MARK: - SHEET ROW

    @ViewBuilder
    private func sheetRow(_ sheet: SharedSheet) -> some View {
        let balance = sheetBalance(sheet)
        let isPositive = balance > 0
        let isEven = balance == 0
        let accentColor: Color = isEven ? .gray : (isPositive ? .green : .red)
        let iconName = isEven ? "equal" : (isPositive ? "arrow.up" : "arrow.down")

        HStack(spacing: 14) {
            // Colored circle icon
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(accentColor)
            }

            // Center: sheet name
            Text(sheet.name ?? NSLocalizedString("sheet", comment: ""))
                .font(.headline)
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer()

            // Right: balance
            Text(sheetBalanceText(sheet))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(accentColor)
                .lineLimit(1)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
        )
    }

    // MARK: - EMPTY STATE

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 56, weight: .thin))
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                Text(NSLocalizedString("Nessun foglio", comment: ""))
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Text(NSLocalizedString("Crea il tuo primo foglio condiviso per iniziare a tracciare le spese.", comment: ""))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button {
                showingAddSheet = true
            } label: {
                Label(NSLocalizedString("Crea foglio", comment: ""), systemImage: "plus")
                    .font(.body)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(.top, 4)

            Spacer()
        }
    }

    // MARK: - BOOTSTRAP USER
    private func bootstrapCurrentUserIfNeeded() {
        guard currentUser.personID == nil else { return }

        if let firstSheet = sheets.first,
           let firstPerson = firstSheet.personsArray.first,
           let id = firstPerson.id {
            currentUser.bootstrapIfNeeded(with: id)
        }
    }

    // MARK: - LOGICA

    private func deleteSheets(at offsets: IndexSet) {
        offsets.map { sheets[$0] }.forEach(viewContext.delete)
        try? viewContext.save()
    }

    private func sheetBalance(_ sheet: SharedSheet) -> Double {
        guard let me = myPerson(in: sheet) else { return 0 }
        return sheet.balance(for: me.id!)
    }

    private func sheetBalanceText(_ sheet: SharedSheet) -> String {
        let value = sheetBalance(sheet)
        let formatted = String(format: "%.2f", abs(value))

        if value == 0 {
            return NSLocalizedString("in pari", comment: "")
        } else if value > 0 {
            return "+\(formatted) €"
        } else {
            return "−\(formatted) €"
        }
    }

    private func totalBalance() -> Double {
        normalized(sheets.reduce(0) { $0 + sheetBalance($1) })
    }

    /// Returns just the formatted amount (e.g. "12.50 €") for the hero card number display.
    private func totalBalanceAmountText() -> String {
        let value = totalBalance()
        if value == 0 {
            return "0.00 €"
        }
        return String(format: "%.2f €", abs(value))
    }

    private func totalBalanceText() -> String {
        let value = totalBalance()
        let formatted = String(format: "%.2f", abs(value))

        if value == 0 {
            return NSLocalizedString("balance_even", comment: "")
        } else if value > 0 {
            return String(
                format: NSLocalizedString("you_are_owed_amount", comment: ""),
                formatted
            )
        } else {
            return String(
                format: NSLocalizedString("you_owe_amount", comment: ""),
                formatted
            )
        }
    }

    private func normalized(_ value: Double) -> Double {
        abs(value) < 0.005 ? 0 : value
    }

    private func balancesPerPerson(sheet: SharedSheet) -> [Person: Double] {
        var balances: [Person: Double] = [:]

        let persons = sheet.personsArray
        let expenses = sheet.expensesArray

        persons.forEach { balances[$0] = 0 }

        for expense in expenses {
            guard
                let payer = expense.paidBy,
                let split = expense.splitBetween as? Set<Person>,
                !split.isEmpty
            else { continue }

            let share = expense.amount / Double(split.count)

            balances[payer, default: 0] += expense.amount
            for person in split {
                balances[person, default: 0] -= share
            }
        }

        return balances
    }

    private func myPerson(in sheet: SharedSheet) -> Person? {
        sheet.personsArray.first { person in
            person.name?.lowercased() == "io"
                || person.name?.lowercased() == NSLocalizedString("Me", comment: "").lowercased()
        }
    }
}
