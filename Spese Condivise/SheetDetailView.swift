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
        List {
            if let persons = sheet.persons as? Set<Person>, !persons.isEmpty {
                Section(header: Text(NSLocalizedString("Persone", comment: "people"))) {
                    
                    let balances = balancesPerPerson(sheet: sheet)
                    
                    ForEach(sheet.personsArray) { person in
                        let value = balances[person] ?? 0
                        let isMe = person.id == currentUser.personID
                        
                        HStack {
                            Text(person.name ?? "—")
                            Spacer()
                            Text(personBalanceText(value, isMe: isMe))
                                .foregroundColor(balanceColor(value))
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
            
            Section {
                ForEach(expenses) { expense in
                    Button {
                        activeModal = .edit(expense)
                    } label: {
                        ExpenseRowView(expense: expense)
                    }
                }
                .onDelete(perform: deleteExpenses)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(sheet.name ?? "Foglio")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    activeModal = .add
                } label: {
                    Image(systemName: "plus")
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: openShare) {
                    Image(systemName: "person.crop.circle.badge.plus")
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    newPersonName = ""
                    showAddPersonAlert = true
                } label: {
                    Image(systemName: "person.badge.plus")
                }
            }
        }
            // GESTIONE MODAL AGGIUNGI/MODIFICA
            // GESTIONE MODAL AGGIUNGI/MODIFICA/SHARE
        .sheet(item: $activeModal) { modal in
            switch modal {
                case .add:
                    AddExpenseView(sheetID: sheet.objectID)
                case .edit(let expense):
                    AddExpenseView(expenseToEdit: expense)
                case .share(let url):
                    ActivityView(activityItems: [url])
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
        let coreDataContainer = PersistenceController.shared.container
        let ckContainer = CKContainer(identifier: "iCloud.com.marcolagana.SharedExpenses")

        if coreDataContainer.viewContext.hasChanges {
            try? coreDataContainer.viewContext.save()
        }

            // Se esiste già una share, usala direttamente senza ricrearla
        if let existing = (try? coreDataContainer.fetchShares(matching: [sheet.objectID]))?[sheet.objectID] {
            existing[CKShare.SystemFieldKey.title] = sheet.name ?? "Foglio Condiviso"
            existing.publicPermission = .readOnly
            uploadAndPresent(existing, using: ckContainer)
            return
        }

            // Altrimenti crea una nuova share
        coreDataContainer.share([sheet], to: nil) { _, share, _, error in
            if let error = error {
                DispatchQueue.main.async {
                    self.shareErrorMessage = self.errorMessage(for: error)
                    self.showingShareError = true
                }
                return
            }
            guard let ckShare = share else {
                DispatchQueue.main.async {
                    self.shareErrorMessage = "Impossibile creare la condivisione."
                    self.showingShareError = true
                }
                return
            }
            ckShare[CKShare.SystemFieldKey.title] = self.sheet.name ?? "Foglio Condiviso"
            ckShare.publicPermission = .readOnly
            self.uploadAndPresent(ckShare, using: ckContainer)
        }
    }

    private func uploadAndPresent(_ share: CKShare, using ckContainer: CKContainer) {
        let op = CKModifyRecordsOperation(recordsToSave: [share], recordIDsToDelete: nil)
        op.savePolicy = .changedKeys
        op.configuration.timeoutIntervalForRequest = 15
        op.configuration.timeoutIntervalForResource = 15
        op.modifyRecordsResultBlock = { result in
            DispatchQueue.main.async {
                switch result {
                    case .success:
                        if let url = share.url {
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
