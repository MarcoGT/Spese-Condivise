import SwiftUI
import CoreData
import CloudKit

struct SheetDetailView: View {
    
    @ObservedObject var sheet: SharedSheet
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var persistence: PersistenceController
    
    @FetchRequest private var expenses: FetchedResults<Expense>
    
    @State private var activeModal: ActiveModal?
    @State private var showShareSheet = false
    @State private var cloudShare: CKShare?
    
    enum ActiveModal: Identifiable {
        case add
        case edit(Expense)
        
        var id: NSManagedObjectID {
            switch self {
                case .add: return NSManagedObjectID()
                case .edit(let expense): return expense.objectID
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
            
            Section {
                Text(balanceText())
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(balance() >= 0 ? .green : .red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
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
                Button {
                    openShare()
                } label: {
                    Image(systemName: "person.crop.circle.badge.plus")
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let cloudShare {
                CloudSharingView(
                    share: cloudShare,
                    container: CKContainer(identifier: "iCloud.com.marcolagana.SharedExpenses")
                )
            }
        }
        .sheet(item: $activeModal) { modal in
            switch modal {
                case .add:
                    AddExpenseView(sheetID: sheet.objectID)
                case .edit(let expense):
                    AddExpenseView(expenseToEdit: expense)
            }
        }
    }
    
        // MARK: - CONDIVISIONE (CORE)
    
    private func openShare() {
        Task {
            let container = persistence.container
            let context = persistence.container.viewContext
            
            do {
                    // 1️⃣ Fetch share esistente
                let sharesByObjectID = try await container.fetchShares(
                    matching: [sheet.objectID]
                )
                
                if let existing = sharesByObjectID[sheet.objectID] {
                    await MainActor.run {
                        cloudShare = existing
                        showShareSheet = true
                    }
                    return
                }
                
                    // 2️⃣ Crea nuovo share
                try await container.share([sheet], to: nil)
                
                    // 3️⃣ Rifetch (OBBLIGATORIO)
                let newShares = try await container.fetchShares(
                    matching: [sheet.objectID]
                )
                
                guard let share = newShares[sheet.objectID] else {
                    print("❌ Share non trovato dopo creazione")
                    return
                }
                
                    // 4️⃣ Configura correttamente lo share
                share.publicPermission = .readWrite
                share[CKShare.SystemFieldKey.title] = sheet.name ?? NSLocalizedString("shared sheet", comment: "shared sheet")
                
                try context.save()
                
                await MainActor.run {
                    cloudShare = share
                    showShareSheet = true
                }
                
            } catch {
                print("❌ Share error:", error)
            }
        }
    }





    
        // MARK: - LOGICA
    
        // MARK: - LOGICA
    
    private func balance() -> Double {
        let raw = expenses.reduce(0) {
            $0 + ($1.paidByMe ? $1.amount : -$1.amount)
        }
        return abs(raw) < 0.005 ? 0 : raw
    }
    
    private func balanceText() -> String {
        let value = balance()
        let formatted = String(format: "%.2f", abs(value))
        
        if value == 0 {
            return NSLocalizedString("balance_even", comment: "Balance is even")
        }
        
        if value > 0 {
                // Gli altri ti devono
            return String(
                format: NSLocalizedString("you_are_owed_amount", comment: "Others owe you money"),
                formatted
            )
        } else {
                // Tu devi
            return String(
                format: NSLocalizedString("you_owe_amount", comment: "You owe money"),
                formatted
            )
        }
    }
    
    private func deleteExpenses(at offsets: IndexSet) {
        offsets.map { expenses[$0] }.forEach(viewContext.delete)
        
        sheet.lastUpdated = Date()
        
        try? viewContext.save()
    }

}
