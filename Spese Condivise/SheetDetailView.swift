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
        request.predicate = NSPredicate(format: "sheet == %@", sheet)

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
                                    PersonBalanceCard(
                                        person: person,
                                        value: value,
                                        isMe: isMe,
                                        balanceColor: balanceColor(value),
                                        balanceText: personBalanceText(value, isMe: isMe)
                                    )
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                    } header: {
                        SectionHeader(title: NSLocalizedString("Persone", comment: "people"))
                    }
                }

                // MARK: Expenses section
                Section {
                    if expenses.isEmpty {
                        EmptyExpensesView()
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(expenses) { expense in
                            Button {
                                activeModal = .edit(expense)
                            } label: {
                                ExpenseRowView(expense: expense)
                                    .background(Color(.systemBackground))
                                    .cornerRadius(14)
                                    .shadow(color: Color.black.opacity(0.07), radius: 10, x: 0, y: 4)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        }
                        .onDelete(perform: deleteExpenses)
                    }
                } header: {
                    SectionHeader(title: NSLocalizedString("Spese", comment: "expenses"))
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle(sheet.name ?? NSLocalizedString("sheet", comment: ""))
        .toolbar {
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

        // Se esiste già una share, usala direttamente senza ricrearla
        if let existing = (try? coreDataContainer.fetchShares(matching: [sheet.objectID]))?[sheet.objectID] {
            // Solo il proprietario può modificare i permessi della share.
            // I partecipanti non possono — CloudKit lancia un'eccezione.
            if existing.currentUserParticipant?.role == .owner {
                existing[CKShare.SystemFieldKey.title] = sheet.name ?? "Foglio Condiviso"
                existing.publicPermission = .readWrite
            }
            uploadAndPresent(existing, using: ckContainer)
            return
        }

        // Altrimenti crea una nuova share
        coreDataContainer.share([sheet], to: nil) { _, share, _, error in
            if let error = error {
                DispatchQueue.main.async {
                    self.isPreparingShare = false
                    self.shareErrorMessage = self.errorMessage(for: error)
                    self.showingShareError = true
                }
                return
            }
            guard let ckShare = share else {
                DispatchQueue.main.async {
                    self.isPreparingShare = false
                    self.shareErrorMessage = NSLocalizedString("share_creation_failed", comment: "")
                    self.showingShareError = true
                }
                return
            }
            ckShare[CKShare.SystemFieldKey.title] = self.sheet.name ?? "Foglio Condiviso"
            ckShare.publicPermission = .readWrite
            // Aspetta che NSPersistentCloudKitContainer finisca l'upload dei record
            // prima di presentare l'URL — altrimenti il destinatario accetta una
            // share vuota (race condition).
            self.waitForExportThenPresent(ckShare, using: ckContainer)
        }
    }

    /// Aspetta che NSPersistentCloudKitContainer esporti i record su CloudKit
    /// (eventi di export completati DOPO la creazione della share),
    /// poi chiama uploadAndPresent. Fallback dopo 12 secondi.
    private func waitForExportThenPresent(_ share: CKShare, using ckContainer: CKContainer) {
        // Salva il context per innescare subito un ciclo di sync
        let coreDataContainer = PersistenceController.shared.container
        if coreDataContainer.viewContext.hasChanges {
            try? coreDataContainer.viewContext.save()
        }

        let shareCreatedAt = Date()
        var observer: NSObjectProtocol?
        var fired = false

        let fire: () -> Void = {
            guard !fired else { return }
            fired = true
            if let obs = observer { NotificationCenter.default.removeObserver(obs) }
            self.uploadAndPresent(share, using: ckContainer)
        }

        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard
                let event = notification.userInfo?[
                    NSPersistentCloudKitContainer.eventNotificationUserInfoKey
                ] as? NSPersistentCloudKitContainer.Event,
                event.type == .export,
                event.endDate != nil,
                event.error == nil,
                // Solo eventi di export iniziati DOPO che la share è stata creata
                event.startDate >= shareCreatedAt
            else { return }
            fire()
        }

        // Fallback: se non arriva conferma entro 12 secondi, proviamo comunque
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { fire() }
    }

    private func uploadAndPresent(_ share: CKShare, using ckContainer: CKContainer) {
        let op = CKModifyRecordsOperation(recordsToSave: [share], recordIDsToDelete: nil)
        op.savePolicy = .changedKeys
        op.configuration.timeoutIntervalForRequest = 15
        op.configuration.timeoutIntervalForResource = 15

        // CloudKit restituisce il record aggiornato (con URL) nel perRecordSaveBlock,
        // non nell'oggetto locale passato all'operazione.
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
                        let url = savedShare?.url ?? share.url
                        if let url {
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
        sheet.lastUpdated = Date()

        try? viewContext.save()
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
        let expenses = sheet.expensesArray

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
        if abs(value) < 0.01 { return NSLocalizedString("In pari", comment: "") }
        let amount = String(format: "%.2f €", abs(value))

        if value > 0 {
            return isMe ? "Ti devono \(amount)" : "Gli devono \(amount)"
        } else {
            return isMe ? "Devi \(amount)" : "Deve \(amount)"
        }
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

    private var balanceLabel: String {
        if abs(value) < 0.01 { return "pari" }
        if value > 0 { return isMe ? "ti devono" : "gli devono" }
        return isMe ? "devi" : "deve"
    }

    private var formattedAmount: String {
        if abs(value) < 0.01 { return "0.00 €" }
        return String(format: "%.2f €", abs(value))
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
    }
}

private struct EmptyExpensesView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "plus.circle")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("Nessuna spesa ancora")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
