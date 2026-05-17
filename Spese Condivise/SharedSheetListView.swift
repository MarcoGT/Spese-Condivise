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
    @State private var lastSeenRefresh = Date()
    @State private var sheetToCustomize: SharedSheet? = nil
    // Emoji e colori per foglio — aggiornati subito al salvataggio
    @State private var sheetEmojis:  [NSManagedObjectID: String] = [:]
    @State private var sheetColors:  [NSManagedObjectID: Color]  = [:]

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
                                            .onDisappear { lastSeenRefresh = Date() }
                                    } label: {
                                        SheetRowView(
                                            sheet: sheet,
                                            emoji: sheetEmojis[sheet.objectID],
                                            sheetColor: sheetColors[sheet.objectID] ?? SheetAppearanceStore.shared.color(for: sheet),
                                            balanceText: sheetBalanceText(sheet),
                                            balanceColor: {
                                                let b = sheetBalance(sheet)
                                                return b == 0 ? .gray : (b > 0 ? .green : .red)
                                            }(),
                                            lastSeenRefresh: lastSeenRefresh
                                        )
                                    }
                                    .contextMenu {
                                        Button {
                                            sheetToCustomize = sheet
                                        } label: {
                                            Label(NSLocalizedString("appearance_title", comment: ""), systemImage: "paintpalette")
                                        }
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
            loadSavedAppearances()

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
        .sheet(item: $sheetToCustomize) { sheet in
            SheetAppearanceView(sheet: sheet) { emoji, color in
                // Aggiorna @State subito — SwiftUI ridisegna la riga immediatamente
                if let e = emoji { sheetEmojis[sheet.objectID] = e }
                else { sheetEmojis.removeValue(forKey: sheet.objectID) }
                sheetColors[sheet.objectID] = color
            }
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

    // sheetRow ora è una struct separata — vedi SheetRowView in fondo al file

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

    // MARK: - APPEARANCE

    private func loadSavedAppearances() {
        let store = SheetAppearanceStore.shared
        for sheet in sheets {
            if let e = store.emoji(for: sheet) {
                sheetEmojis[sheet.objectID] = e
            }
            sheetColors[sheet.objectID] = store.color(for: sheet)
        }
    }

    // MARK: - BOOTSTRAP USER
    private func bootstrapCurrentUserIfNeeded() {
        // Cerca sempre la persona "Io/Me" e la imposta come utente corrente —
        // sovrascrive eventuali ID errati salvati in precedenza.
        let meName = NSLocalizedString("Me", comment: "current user") // "Io" in IT, "Me" in EN
        for sheet in sheets {
            let persons = sheet.personsArray
            let match = persons.first(where: { $0.name == meName })
                     ?? persons.first(where: { $0.name?.lowercased() == "io" || $0.name?.lowercased() == "me" })
            if let me = match, let id = me.id {
                currentUser.setPersonID(id)  // corregge anche ID errati già salvati
                return
            }
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
        if value == 0 { return NSLocalizedString("in pari", comment: "") }
        let formatted = AmountFormatter.format(abs(value))
        return value > 0 ? "+\(formatted)" : "−\(formatted)"
    }

    private func totalBalance() -> Double {
        normalized(sheets.reduce(0) { $0 + sheetBalance($1) })
    }

    /// Returns just the formatted amount (e.g. "12,50 €") for the hero card number display.
    private func totalBalanceAmountText() -> String {
        let value = totalBalance()
        return AmountFormatter.format(abs(value))
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
