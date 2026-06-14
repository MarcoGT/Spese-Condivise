import SwiftUI
import CoreData
import CloudKit

struct SheetDetailView: View {

    @ObservedObject var sheet: SharedSheet
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var persistence: PersistenceController
    @EnvironmentObject private var currentUser: CurrentUser

    @FetchRequest private var expenses: FetchedResults<Expense>

    @State private var activeModal: ActiveModal?
    @State private var showAddPersonAlert = false
    @State private var newPersonName = ""
    @State private var showingShareError = false
    @State private var shareErrorMessage = ""
    @State private var isPreparingShare = false
    @State private var showSettleConfirm = false
    @State private var showStatistics = false
    @State private var searchText = ""
    @State private var selectedCategoryFilter: ExpenseCategory? = nil
    @State private var personToClaimAsMe: Person? = nil

    enum ActiveModal: Identifiable {
        case add
        case edit(Expense)
        case share(URL)

        var id: String {
            switch self {
                case .add: return "add"
                case .edit(let expense): return "edit-\(expense.objectID.uriRepresentation().absoluteString)"
                case .share(let url): return "share-\(url.absoluteString)"
            }
        }
    }

    init(sheet: SharedSheet) {
        self.sheet = sheet

        let request: NSFetchRequest<Expense> = Expense.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \Expense.date, ascending: false)
        ]
        // archived != YES gestisce correttamente anche valori NULL (es. dopo sync CloudKit)
        request.predicate = NSPredicate(format: "sheet == %@ AND archived != YES", sheet)

        _expenses = FetchRequest(fetchRequest: request)
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            List {
                // MARK: Persons section
                if let persons = sheet.persons as? Set<Person>, !persons.isEmpty {
                    Section {
                        let balances = balancesPerPerson(sheet: sheet)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(sheet.personsArray) { person in
                                    let value = balances[person] ?? 0
                                    let isMe = person.id == currentUser.personID
                                    let claimMode = isSharedSheet && !isIdentifiedInSheet
                                    PersonBalanceCard(
                                        person: person,
                                        value: value,
                                        isMe: isMe,
                                        balanceColor: balanceColor(value),
                                        balanceText: personBalanceText(value, isMe: isMe),
                                        onTap: claimMode ? { personToClaimAsMe = person } : nil
                                    )
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())

                        // Banner "chi sei tu?" visibile solo nei fogli condivisi
                        // dove l'utente non si è ancora identificato
                        if isSharedSheet && !isIdentifiedInSheet {
                            HStack(spacing: 10) {
                                Image(systemName: "person.fill.questionmark")
                                    .foregroundColor(.accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(NSLocalizedString("identify_prompt_title", comment: ""))
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Text(NSLocalizedString("identify_prompt_body", comment: ""))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 4)
                            .listRowBackground(Color.accentColor.opacity(0.06))
                        }
                    } header: {
                        SectionHeader(title: NSLocalizedString("Persone", comment: "people"))
                    }
                }

                // MARK: Category filter chips
                if !expenses.isEmpty {
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                // "Tutte" chip
                                Button {
                                    selectedCategoryFilter = nil
                                } label: {
                                    Text(NSLocalizedString("all_categories", comment: ""))
                                        .font(.subheadline)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 7)
                                        .background(selectedCategoryFilter == nil ? Color.accentColor : Color(.systemGray5))
                                        .foregroundColor(selectedCategoryFilter == nil ? .white : .primary)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)

                                // Una chip per ogni categoria presente nelle spese
                                ForEach(usedCategories, id: \.self) { cat in
                                    let isSelected = selectedCategoryFilter == cat
                                    Button {
                                        selectedCategoryFilter = isSelected ? nil : cat
                                    } label: {
                                        HStack(spacing: 5) {
                                            Image(systemName: cat.icon)
                                                .font(.caption)
                                            Text(cat.localizedName)
                                                .font(.subheadline)
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 7)
                                        .background(isSelected ? cat.color : Color(.systemGray5))
                                        .foregroundColor(isSelected ? .white : .primary)
                                        .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                    }
                }

                // MARK: Expenses section
                Section {
                    if expenses.isEmpty {
                        if isSharedSheet {
                            SharedSyncEmptyView()
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        } else {
                            EmptyExpensesView { activeModal = .add }
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    } else if filteredExpenses.isEmpty {
                        // Nessun risultato per ricerca/filtro
                        VStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary)
                            Text(NSLocalizedString("no_results", comment: ""))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    } else {
                        ForEach(filteredExpenses) { expense in
                            let isNew = (expense.createdAt ?? .distantPast) > LastSeenStore.lastSeen(for: sheet)
                            Button {
                                activeModal = .edit(expense)
                            } label: {
                                ExpenseRowView(expense: expense)
                                    .background(Color(.systemBackground))
                                    .cornerRadius(14)
                                    .shadow(color: Color.black.opacity(0.07), radius: 10, x: 0, y: 4)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(Color.blue.opacity(isNew ? 0.5 : 0), lineWidth: 1.5)
                                    )
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    activeModal = .edit(expense)
                                } label: {
                                    Label(NSLocalizedString("edit", comment: ""), systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
                        .onDelete(perform: deleteExpenses)
                    }
                } header: {
                    SectionHeader(title: NSLocalizedString("Spese", comment: "expenses"))
                }

                // MARK: Archive link
                if !sheet.settlementsArray.isEmpty {
                    Section {
                        NavigationLink {
                            ArchiveView(sheet: sheet)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "archivebox.fill")
                                    .foregroundColor(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(NSLocalizedString("archive_title", comment: ""))
                                        .font(.body)
                                        .fontWeight(.medium)
                                    Text(String(
                                        format: NSLocalizedString("archive_settlement_count", comment: ""),
                                        sheet.settlementsArray.count
                                    ))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowBackground(Color(.systemBackground))
                    }
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle(sheet.name ?? NSLocalizedString("sheet", comment: ""))
        .searchable(
            text: $searchText,
            prompt: NSLocalizedString("search_expenses", comment: "")
        )
        .onAppear {
            LastSeenStore.markSeen(for: sheet)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showStatistics = true
                } label: {
                    Image(systemName: "chart.bar.xaxis")
                }
                .labelStyle(.iconOnly)
                .disabled(expenses.isEmpty)
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    activeModal = .add
                } label: {
                    Image(systemName: "plus")
                }
                .labelStyle(.iconOnly)
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: openShare) {
                    if isPreparingShare {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "person.crop.circle.badge.plus")
                    }
                }
                .disabled(isPreparingShare)
                .labelStyle(.iconOnly)
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    newPersonName = ""
                    showAddPersonAlert = true
                } label: {
                    Image(systemName: "person.badge.plus")
                }
                .labelStyle(.iconOnly)
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showSettleConfirm = true
                } label: {
                    Image(systemName: "checkmark.circle")
                }
                .labelStyle(.iconOnly)
                .disabled(expenses.isEmpty)
            }
        }
        // GESTIONE MODAL AGGIUNGI/MODIFICA/SHARE
        .sheet(item: $activeModal) { modal in
            switch modal {
                case .add:
                    AddExpenseView(sheetID: sheet.objectID)
                case .edit(let expense):
                    AddExpenseView(expenseToEdit: expense)
                case .share(let url):
                    ActivityView(activityItems: [url]) {
                        activeModal = nil
                    }
            }
        }
        // STATISTICHE
        .sheet(isPresented: $showStatistics) {
            StatisticsView(sheet: sheet)
        }
        // CONFERMA AZZERAMENTO SALDO
        .confirmationDialog(
            NSLocalizedString("settle_confirm_title", comment: ""),
            isPresented: $showSettleConfirm,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("settle_confirm_action", comment: ""), role: .destructive) {
                performSettle()
            }
            Button(NSLocalizedString("Annulla", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("settle_confirm_message", comment: ""))
        }
        // GESTIONE ERRORI CONDIVISIONE
        .alert("Errore condivisione", isPresented: $showingShareError) {
            Button("OK") {}
        } message: {
            Text(shareErrorMessage)
        }
        // GESTIONE ALERT AGGIUNGI PERSONA
        .alert("Aggiungi persona", isPresented: $showAddPersonAlert) {
            TextField("Nome", text: $newPersonName)
            Button("Annulla", role: .cancel) {}
            Button("Aggiungi") { addPerson() }
        } message: {
            Text("Inserisci il nome della persona")
        }
        // CONFERMA IDENTIFICAZIONE PERSONA
        .confirmationDialog(
            NSLocalizedString("identify_confirm_title", comment: ""),
            isPresented: Binding(
                get: { personToClaimAsMe != nil },
                set: { if !$0 { personToClaimAsMe = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let person = personToClaimAsMe {
                Button(String(format: NSLocalizedString("identify_confirm_action", comment: ""), person.name ?? "")) {
                    currentUser.setPersonID(person.id!)
                    personToClaimAsMe = nil
                }
            }
            Button(NSLocalizedString("Annulla", comment: ""), role: .cancel) {
                personToClaimAsMe = nil
            }
        } message: {
            if let person = personToClaimAsMe {
                Text(String(format: NSLocalizedString("identify_confirm_message", comment: ""), person.name ?? ""))
            }
        }
    }

    // MARK: - FILTRO

    private var usedCategories: [ExpenseCategory] {
        let raw = Set(expenses.compactMap { $0.category })
        return ExpenseCategory.allCases.filter { raw.contains($0.rawValue) }
    }

    private var filteredExpenses: [Expense] {
        expenses.filter { expense in
            let matchesSearch = searchText.isEmpty
                || (expense.note?.localizedCaseInsensitiveContains(searchText) == true)
                || (expense.paidBy?.name?.localizedCaseInsensitiveContains(searchText) == true)
            let matchesCategory = selectedCategoryFilter == nil
                || expense.category == selectedCategoryFilter?.rawValue
            return matchesSearch && matchesCategory
        }
    }

    // MARK: - AZZERAMENTO SALDO

    private func performSettle() {
        try? SettlementService.performSettlement(sheet: sheet, context: viewContext)
    }

    // MARK: - CONDIVISIONE (CORE)

    private func openShare() {
        guard !isPreparingShare else { return }
        isPreparingShare = true

        let coreDataContainer = PersistenceController.shared.container
        let ckContainer = CKContainer(identifier: "iCloud.com.marcolagana.SharedExpenses")

        if coreDataContainer.viewContext.hasChanges {
            try? coreDataContainer.viewContext.save()
        }

        // Se esiste già una share, usala direttamente
        if let existing = (try? coreDataContainer.fetchShares(matching: [sheet.objectID]))?[sheet.objectID] {
            let isOwner = existing.currentUserParticipant?.role == .owner

            if isOwner {
                // Il proprietario può aggiornare titolo e permessi
                existing[CKShare.SystemFieldKey.title] = sheet.name ?? "Foglio Condiviso"
                existing.publicPermission = .readWrite

                if let url = existing.url {
                    // URL già disponibile: aggiorna titolo/permessi in background e presenta subito
                    uploadShareMetadata(existing, using: ckContainer)
                    isPreparingShare = false
                    activeModal = .share(url)
                } else {
                    // URL non ancora disponibile: upload e poi presenta
                    uploadAndPresent(existing, using: ckContainer)
                }
            } else {
                // Partecipante (non proprietario): usa la URL della share esistente
                isPreparingShare = false
                if let url = existing.url {
                    activeModal = .share(url)
                } else {
                    shareErrorMessage = NSLocalizedString("Link non disponibile. Riprova tra qualche secondo.", comment: "")
                    showingShareError = true
                }
            }
            return
        }

        // Crea una nuova share (prima volta, solo per il proprietario)
        // NSPersistentCloudKitContainer carica il record su CloudKit e torna
        // con share.url già valorizzata nel callback.
        coreDataContainer.share([sheet], to: nil) { _, share, _, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.isPreparingShare = false
                    self.shareErrorMessage = self.errorMessage(for: error)
                    self.showingShareError = true
                    return
                }
                guard let ckShare = share else {
                    self.isPreparingShare = false
                    self.shareErrorMessage = NSLocalizedString("share_creation_failed", comment: "")
                    self.showingShareError = true
                    return
                }
                ckShare[CKShare.SystemFieldKey.title] = self.sheet.name ?? "Foglio Condiviso"
                ckShare.publicPermission = .readWrite

                if let url = ckShare.url {
                    // Share già caricata da NSPersistentCloudKitContainer: aggiorna metadati in background
                    self.uploadShareMetadata(ckShare, using: ckContainer)
                    self.isPreparingShare = false
                    self.activeModal = .share(url)
                } else {
                    // Caso raro: URL non ancora disponibile, carica e presenta
                    self.uploadAndPresent(ckShare, using: ckContainer)
                }
            }
        }
    }

    // Aggiorna titolo e permessi della share senza attendere il risultato (fire-and-forget).
    private func uploadShareMetadata(_ share: CKShare, using ckContainer: CKContainer) {
        let op = CKModifyRecordsOperation(recordsToSave: [share], recordIDsToDelete: nil)
        op.savePolicy = .changedKeys
        op.configuration.timeoutIntervalForRequest = 20
        op.configuration.timeoutIntervalForResource = 20
        ckContainer.privateCloudDatabase.add(op)
    }

    // Upload completo della share: attende il risultato per ricavare la URL.
    private func uploadAndPresent(_ share: CKShare, using ckContainer: CKContainer) {
        let op = CKModifyRecordsOperation(recordsToSave: [share], recordIDsToDelete: nil)
        op.savePolicy = .changedKeys
        op.configuration.timeoutIntervalForRequest = 20
        op.configuration.timeoutIntervalForResource = 20

        var savedShare: CKShare?
        op.perRecordSaveBlock = { _, result in
            if case .success(let record) = result, let ckShare = record as? CKShare {
                savedShare = ckShare
            }
        }

        op.modifyRecordsResultBlock = { result in
            DispatchQueue.main.async {
                self.isPreparingShare = false
                switch result {
                    case .success:
                        if let url = savedShare?.url ?? share.url {
                            self.activeModal = .share(url)
                        } else {
                            self.shareErrorMessage = NSLocalizedString("Link non disponibile. Riprova tra qualche secondo.", comment: "")
                            self.showingShareError = true
                        }
                    case .failure(let error):
                        self.shareErrorMessage = self.errorMessage(for: error)
                        self.showingShareError = true
                }
            }
        }
        ckContainer.privateCloudDatabase.add(op)
    }

    private func errorMessage(for error: Error) -> String {
        if let ckError = error as? CKError {
            switch ckError.code {
                case .notAuthenticated:
                    return "Devi essere connesso con il tuo Apple ID. Vai in Impostazioni > iCloud."
                case .accountTemporarilyUnavailable:
                    return "L'account iCloud non è ancora pronto. Attendi qualche secondo e riprova."
                case .networkFailure, .networkUnavailable:
                    return "Connessione internet non disponibile. Riprova più tardi."
                case .quotaExceeded:
                    return "Spazio iCloud insufficiente. Libera spazio e riprova."
                default:
                    return "Errore durante la condivisione:\n\(ckError.localizedDescription)"
            }
        }
        return "Errore durante la condivisione:\n\(error.localizedDescription)"
    }

    private func addPerson() {
        let trimmed = newPersonName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let person = Person(context: viewContext)
        person.id = UUID()
        person.name = trimmed
        person.sheet = sheet

        if let sheetStore = sheet.objectID.persistentStore {
            viewContext.assign(person, to: sheetStore)
        }

        sheet.lastUpdated = Date()
        try? viewContext.save()
    }

    // MARK: - IDENTITÀ FOGLIO CONDIVISO

    private var isSharedSheet: Bool {
        sheet.objectID.persistentStore === persistence.sharedPersistentStore
    }

    private var isIdentifiedInSheet: Bool {
        guard let myID = currentUser.personID else { return false }
        return sheet.personsArray.contains { $0.id == myID }
    }

    // MARK: - LOGICA BILANCI

    private func deleteExpenses(at offsets: IndexSet) {
        offsets.map { expenses[$0] }.forEach(viewContext.delete)
        sheet.lastUpdated = Date()
        try? viewContext.save()
    }

    func balancesPerPerson(sheet: SharedSheet) -> [Person: Double] {
        var balances: [Person: Double] = [:]
        let persons = sheet.personsArray
        let expenses = sheet.activeExpensesArray  // solo spese attive

        persons.forEach { balances[$0] = 0 }

        for expense in expenses {
            guard let payer = expense.paidBy,
                  let split = expense.splitBetween as? Set<Person>,
                  !split.isEmpty else { continue }

            let share = expense.amount / Double(split.count)
            balances[payer, default: 0] += expense.amount
            for person in split {
                balances[person, default: 0] -= share
            }
        }
        return balances
    }

    private func balanceColor(_ value: Double) -> Color {
        if abs(value) < 0.01 { return .secondary }
        return value > 0 ? .green : .red
    }

    func personBalanceText(_ value: Double, isMe: Bool) -> String {
        // Usato solo come label accessibile — testo neutro per qualsiasi persona
        if abs(value) < 0.01 { return NSLocalizedString("In pari", comment: "") }
        let amount = AmountFormatter.format(abs(value))
        return value > 0 ? "\(amount) in credito" : "\(amount) in debito"
    }
}

// MARK: - Supporting Views

private struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline)
            .fontWeight(.semibold)
            .textCase(nil)
            .foregroundColor(.secondary)
            .listRowBackground(Color.clear)
    }
}

private struct PersonBalanceCard: View {
    let person: Person
    let value: Double
    let isMe: Bool
    let balanceColor: Color
    let balanceText: String
    var onTap: (() -> Void)? = nil

    private var balanceLabel: String {
        if abs(value) < 0.01 { return NSLocalizedString("balance_even_short", comment: "") }
        return value > 0
            ? NSLocalizedString("balance_credit", comment: "")
            : NSLocalizedString("balance_debit", comment: "")
    }

    private var formattedAmount: String {
        if abs(value) < 0.01 { return AmountFormatter.format(0) }
        return AmountFormatter.format(abs(value))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(isMe ? .blue : .secondary)
                Text(person.name ?? "—")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .foregroundColor(.primary)
            }

            Spacer(minLength: 4)

            Text(formattedAmount)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundColor(balanceColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(balanceLabel)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
        .frame(width: 130, alignment: .leading)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isMe ? Color.blue.opacity(0.25) : Color.clear, lineWidth: 1.5)
        )
        .shadow(color: Color.black.opacity(0.07), radius: 10, x: 0, y: 4)
        .overlay(alignment: .topTrailing) {
            if onTap != nil {
                Image(systemName: "hand.tap.fill")
                    .font(.caption2)
                    .foregroundColor(.accentColor)
                    .padding(6)
            }
        }
        .onTapGesture {
            onTap?()
        }
    }
}

private struct EmptyExpensesView: View {
    var onAdd: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "plus.circle")
                .font(.system(size: 40))
                .foregroundColor(.accentColor)
            Text(NSLocalizedString("no_expenses_yet", comment: ""))
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .contentShape(Rectangle())
        .onTapGesture { onAdd() }
    }
}

private struct SharedSyncEmptyView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text(NSLocalizedString("shared_sync_empty_title", comment: ""))
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            Text(NSLocalizedString("shared_sync_empty_body", comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
