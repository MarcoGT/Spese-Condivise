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
    @State private var showShareSheet = false
    @State private var cloudShare: CKShare?
    @State private var showAddPersonAlert = false
    @State private var newPersonName = ""
    @State private var showingShareError = false
    @State private var shareErrorMessage = ""
    
    enum ActiveModal: Identifiable {
        case add
        case edit(Expense)
        case share(CKShare)
        
        var id: String {
            switch self {
                case .add: return "add"
                case .edit(let expense): return "edit-\(expense.objectID.uriRepresentation().absoluteString)"
                case .share(let share): return "share-\(share.recordID.recordName)"
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
                case .share(let share):
                    CloudSharingView(
                        share: share,
                        container: CKContainer(identifier: "iCloud.com.marcolagana.SharedExpenses")
                    )
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
            // GESTIONE SHARING SHEET (Separato per evitare conflitti SwiftUI)
        .background(
            EmptyView()
                .sheet(isPresented: $showShareSheet) {
                    if let share = cloudShare {
                        CloudSharingView(
                            share: share,
                            container: CKContainer(identifier: "iCloud.com.marcolagana.SharedExpenses")
                        )
                    }
                }
        )
    }
    
        // MARK: - CONDIVISIONE (CORE)
    
    
    private func openShare() {
        let coreDataContainer = PersistenceController.shared.container
        let ckContainer = CKContainer(identifier: "iCloud.com.marcolagana.SharedExpenses")

            // Salva prima di condividere
        if coreDataContainer.viewContext.hasChanges {
            try? coreDataContainer.viewContext.save()
        }

            // preparationHandler: viene chiamato prima che il controller mostri l'UI.
            // Creiamo/recuperiamo la share, la salviamo esplicitamente su CloudKit
            // (così ha un URL), poi chiamiamo il completion.
        let sharingController = UICloudSharingController { _, completion in
            Task {
                do {
                    let share = try await CloudShareManager.shared.createOrFetchShare(
                        for: self.sheet.objectID,
                        in: coreDataContainer.viewContext,
                        container: coreDataContainer
                    )
                    share[CKShare.SystemFieldKey.title] = self.sheet.name ?? "Foglio Condiviso"

                        // Se la share ha già un URL è già salvata su CloudKit.
                    if share.url != nil {
                        completion(share, ckContainer, nil)
                        return
                    }

                        // Altrimenti la carichiamo esplicitamente sul private database
                        // prima di passarla al controller (serve per generare l'URL).
                    let op = CKModifyRecordsOperation(recordsToSave: [share], recordIDsToDelete: nil)
                    op.savePolicy = .changedKeys
                    op.modifyRecordsResultBlock = { result in
                        switch result {
                            case .success:
                                completion(share, ckContainer, nil)
                            case .failure(let error):
                                completion(nil, nil, error)
                        }
                    }
                    ckContainer.privateCloudDatabase.add(op)
                } catch {
                    completion(nil, nil, error)
                }
            }
        }

        sharingController.delegate = SharingDelegate.shared
        sharingController.availablePermissions = [.allowPublic, .allowReadOnly, .allowPrivate]
        sharingController.modalPresentationStyle = .formSheet

        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }
        root.present(sharingController, animated: true)
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
