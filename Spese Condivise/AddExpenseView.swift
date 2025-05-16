import SwiftUI
import CoreData

struct AddExpenseView: View {
    
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
        // MODE
    private let sheetID: NSManagedObjectID?
    private let expenseToEdit: Expense?
    
        // FIELDS
    @State private var amount: String = ""
    @State private var note: String = ""
    @State private var date: Date = Date()
    @State private var paidByMe: Bool = true
    
        // INIT — ADD
    init(sheetID: NSManagedObjectID) {
        self.sheetID = sheetID
        self.expenseToEdit = nil
    }
    
        // INIT — EDIT
    init(expenseToEdit: Expense) {
        self.sheetID = nil
        self.expenseToEdit = expenseToEdit
    }
    
    var body: some View {
        NavigationView {
            Form {
                
                Section(header: Text("Importo")) {
                    TextField("0,00", text: $amount)
                        .keyboardType(.decimalPad)
                }
                
                Section(header: Text("Descrizione")) {
                    TextField("Es. Cena, benzina…", text: $note)
                }
                
                Section(header: Text("Data")) {
                    DatePicker(
                        "Data",
                        selection: $date,
                        displayedComponents: .date
                    )
                }
                
                Section {
                    Toggle("Pagato da me", isOn: $paidByMe)
                }
            }
            .navigationTitle(expenseToEdit == nil ? NSLocalizedString("new expense", comment: "new expense") : NSLocalizedString("edit expense", comment: "edit expense"))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("cancel", comment: "cancel")) {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("save", comment: "save")) {
                        save()
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear {
                loadIfNeeded()
            }
        }
    }
    
        // MARK: - LOGICA
    
    private var canSave: Bool {
        Double(amount.replacingOccurrences(of: ",", with: ".")) != nil
    }
    
    private func loadIfNeeded() {
        guard let expense = expenseToEdit else { return }
        
        amount = String(format: "%.2f", expense.amount)
        note = expense.note ?? ""
        date = expense.date ?? Date()
        paidByMe = expense.paidByMe
    }
    
    private func save() {
        
        let value = Double(amount.replacingOccurrences(of: ",", with: ".")) ?? 0
        
        if let expense = expenseToEdit {
                // ✏️ EDIT
            expense.amount = value
            expense.note = note
            expense.date = date
            expense.paidByMe = paidByMe
            
            expense.sheet?.lastUpdated = Date()
            
        } else if let sheetID = sheetID,
                  let sheet = try? viewContext.existingObject(with: sheetID) as? SharedSheet {
            
                // ➕ ADD
            let expense = Expense(context: viewContext)
            expense.id = UUID()
            expense.amount = value
            expense.note = note
            expense.date = date
            expense.paidByMe = paidByMe
            expense.sheet = sheet
            
            sheet.lastUpdated = Date()
        }
        
        do {
            
            try viewContext.save()
            dismiss()
        } catch {
            print("❌ Errore salvataggio spesa: \(error)")
        }
    }
}
