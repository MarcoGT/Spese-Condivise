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
    
        // MARK: - BODY
    var body: some View {
        ZStack {
            
            NavigationView {
                List {
                    
                        // 🔹 SALDO TOTALE
                    Section {
                        VStack(spacing: 6) {
                            Text(NSLocalizedString("total", comment: ""))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text(totalBalanceText())
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(totalBalance() >= 0 ? .green : .red)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    
                        // 🔹 ELENCO FOGLI
                    Section {
                        ForEach(sheets) { sheet in
                            NavigationLink {
                                SheetDetailView(sheet: sheet)
                            } label: {
                                HStack {
                                    Text(sheet.name ?? NSLocalizedString("sheet", comment: ""))
                                    Spacer()
                                    Text(sheetBalanceText(sheet))
                                        .foregroundColor(sheetBalance(sheet) >= 0 ? .green : .red)
                                }
                            }
                        }
                        .onDelete(perform: deleteSheets)
                    }
                }
                .listStyle(.insetGrouped)
                .navigationTitle(NSLocalizedString("Shared Expenses", comment: ""))
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        EditButton()
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showingAddSheet = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
                .sheet(isPresented: $showingAddSheet) {
                    AddSharedSheetView()
                }
            }
            
                // 🔹 OVERLAY SYNC (non-blocking)
            if syncState.showOverlay {
                VStack {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text(NSLocalizedString("Sincronizzazione…", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .cornerRadius(20)
                    .padding(.top, 8)
                    Spacer()
                }
                .allowsHitTesting(false)
            }
        }
        .onAppear {
            bootstrapCurrentUserIfNeeded()
            
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
        
            // inizializza TUTTI a 0
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
