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
    @State private var selectedPayer: Person?
    @State private var selectedParticipants: Set<Person> = []

    
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
                
                Section(header: Text(NSLocalizedString("Importo", comment: "amount"))) {
                    TextField("0,00", text: $amount)
                        .keyboardType(.decimalPad)
                }
                
                Section(header: Text(NSLocalizedString("Descrizione", comment: "description"))) {
                    TextField(
                        NSLocalizedString("Es. Cena, benzina…", comment: "example"),
                        text: $note
                    )
                }
                
                Section(header: Text(NSLocalizedString("Data", comment: "date"))) {
                    DatePicker(
                        NSLocalizedString("Data", comment: "date"),
                        selection: $date,
                        displayedComponents: .date
                    )
                }
                
                Section(header: Text(NSLocalizedString("paid by", comment: "paid by"))) {
                    Picker(
                        NSLocalizedString("Pagato da", comment: "paid by picker"),
                        selection: $selectedPayer
                    ) {
                        ForEach(persons) { person in
                            Text(person.name ?? "—")
                                .tag(Optional(person))
                        }
                    }
                }
                
                Section(header: Text(NSLocalizedString("Per chi è la spesa", comment: "split between"))) {
                    ForEach(persons) { person in
                        Button {
                            toggleParticipant(person)
                        } label: {
                            HStack {
                                Text(person.name ?? "—")
                                Spacer()
                                if selectedParticipants.contains(where: { $0.objectID == person.objectID }) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }

                                
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

            }
            .navigationTitle(
                expenseToEdit == nil
                ? NSLocalizedString("new expense", comment: "new expense")
                : NSLocalizedString("edit expense", comment: "edit expense")
            )
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
    
        // MARK: - DATI
    
    private var sheet: SharedSheet? {
        if let expense = expenseToEdit {
            return expense.sheet
        }
        
        if let sheetID = sheetID {
            return try? viewContext.existingObject(with: sheetID) as? SharedSheet
        }
        
        return nil
    }
    
    private var persons: [Person] {
        sheet?.personsArray ?? []
    }
    
        // MARK: - LOGICA
    
    private var canSave: Bool {
        let value = Double(amount.replacingOccurrences(of: ",", with: "."))
        return value != nil && selectedPayer != nil && !selectedParticipants.isEmpty
    }

    
    private func loadIfNeeded() {
        if let expense = expenseToEdit {
            amount = String(format: "%.2f", expense.amount)
            note = expense.note ?? ""
            date = expense.date ?? Date()
            selectedPayer = expense.paidBy
            
                // EDIT → ripristina split
            if let set = expense.splitBetween as? Set<Person> {
                selectedParticipants = Set(
                    set.compactMap { participant in
                        persons.first(where: { $0.objectID == participant.objectID })
                    }
                )
            }


        } else {
                // ADD → default: tutti
            selectedPayer = persons.first
            selectedParticipants = Set(persons)
        }
    }

    
    private func toggleParticipant(_ person: Person) {
        if let existing = selectedParticipants.first(where: { $0.objectID == person.objectID }) {
            selectedParticipants.remove(existing)
        } else {
            selectedParticipants.insert(person)
        }
    }


    
    private func save() {
        guard
            let value = Double(amount.replacingOccurrences(of: ",", with: ".")),
            let payer = selectedPayer
        else { return }
        
        if let expense = expenseToEdit {
            expense.amount = value
            expense.note = note
            expense.date = date
            expense.paidBy = payer
            expense.sheet?.lastUpdated = Date()
            expense.splitBetween = NSSet(set: selectedParticipants)
            
        } else if let sheet = sheet {
                // ➕ ADD
            let expense = Expense(context: viewContext)
            expense.id = UUID()
            expense.amount = value
            expense.note = note
            expense.date = date
            expense.sheet = sheet
            expense.paidBy = payer
            expense.splitBetween = NSSet(set: selectedParticipants)
            
            sheet.lastUpdated = Date()
        }
        
        do {
            try viewContext.save()
            dismiss()
        } catch {
            print("❌ Errore salvataggio spesa:", error)
        }
    }
}

