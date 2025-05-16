import SwiftUI
import CoreData

struct SharedSheetListView: View {
    
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var syncState: AppSyncState
    
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \SharedSheet.lastUpdated, ascending: false)],
        animation: .default
    )
    private var sheets: FetchedResults<SharedSheet>
    
    @State private var showingAddSheet = false
    
    var body: some View {
        ZStack {
            
                // 🔹 CONTENUTO PRINCIPALE
            NavigationView {
                List {
                    
                        // 🔹 SALDO TOTALE
                    Section {
                        VStack(spacing: 6) {
                            Text(NSLocalizedString("total", comment: "total"))
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
                                    Text(sheet.name ?? NSLocalizedString("sheet", comment: "sheet"))
                                    Text("-")
                                    Text(sheet.personName ?? NSLocalizedString("person", comment: "person"))
                                    
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
                .navigationTitle(NSLocalizedString("Shared Expenses", comment: "title"))
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
            
                // 🔹 OVERLAY DI SYNC (QUESTO MANCAVA)
            if syncState.showOverlay {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .transition(.opacity)
                
                VStack(spacing: 12) {
                    ProgressView()
                    Text(NSLocalizedString("Sync in progress", comment: "sync in progress"))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding(24)
                .background(.ultraThinMaterial)
                .cornerRadius(16)
                .shadow(radius: 20)
            }
        }
        .onAppear {
                // mostra solo se non immediato
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                if !syncState.initialSyncCompleted {
                    syncState.showOverlay = true
                }
            }
            
                // fallback di sicurezza (mai freeze)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                syncState.initialSyncCompleted = true
                syncState.showOverlay = false
            }
        }
    }

    
        // MARK: - LOGICA
    
    private func deleteSheets(at offsets: IndexSet) {
        offsets.map { sheets[$0] }.forEach(viewContext.delete)
        try? viewContext.save()
    }
    
    private func sheetBalance(_ sheet: SharedSheet) -> Double {
        let expenses = sheet.expenses as? Set<Expense> ?? []
        let raw = expenses.reduce(0) {
            $0 + ($1.paidByMe ? $1.amount : -$1.amount)
        }
        return normalized(raw)
    }
    
    private func sheetBalanceText(_ sheet: SharedSheet) -> String {
        let value = sheetBalance(sheet)
        let formatted = String(format: "%.2f", abs(value))
        
        if value == 0 { return NSLocalizedString("in pari", comment: "in pari") }
        if value > 0 { return "+\(formatted) €" }
        return "-\(formatted) €"
    }
    
    private func totalBalance() -> Double {
        normalized(sheets.reduce(0) { $0 + sheetBalance($1) })
    }
    
    private func totalBalanceText() -> String {
        let value = totalBalance()
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


    
    private func normalized(_ value: Double) -> Double {
        abs(value) < 0.005 ? 0 : value
    }
}
