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
    @State private var selectedCategory: ExpenseCategory = .other

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
        NavigationStack {
            Form {

                // Big amount field — no header
                Section {
                    HStack {
                        Spacer()
                        TextField("0,00", text: $amount)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 200)
                            .onChange(of: amount) { newValue in
                                let filtered = newValue.filter { $0.isNumber || $0 == "," || $0 == "." }
                                if filtered != newValue { amount = filtered }
                            }
                        Text("€")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }

                // Categoria
                Section(header: Text(NSLocalizedString("category", comment: ""))) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(ExpenseCategory.allCases) { cat in
                                let isSelected = selectedCategory == cat
                                Button {
                                    selectedCategory = cat
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: cat.icon)
                                            .font(.system(size: 13, weight: .semibold))
                                        Text(cat.localizedName)
                                            .font(.subheadline)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(isSelected ? cat.color : cat.color.opacity(0.1))
                                    .foregroundColor(isSelected ? .white : cat.color)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 0))
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
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 10) {
                        ForEach(persons) { person in
                            let isSelected = selectedParticipants.contains(where: { $0.objectID == person.objectID })
                            Button {
                                toggleParticipant(person)
                            } label: {
                                Text(person.name ?? "—")
                                    .font(.subheadline)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity)
                                    .background(
                                        isSelected
                                            ? Color.accentColor
                                            : Color.clear
                                    )
                                    .foregroundColor(
                                        isSelected
                                            ? .white
                                            : .accentColor
                                    )
                                    .clipShape(Capsule())
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(Color.accentColor, lineWidth: isSelected ? 0 : 1.5)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
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
            selectedCategory = ExpenseCategory.from(expense.category)

            // EDIT → ripristina split
            if let set = expense.splitBetween as? Set<Person> {
                selectedParticipants = Set(
                    set.compactMap { participant in
                        persons.first(where: { $0.objectID == participant.objectID })
                    }
                )
            }

        } else {
            // ADD → default pagante: "Io/Me", altrimenti il primo
            let meName = NSLocalizedString("Me", comment: "current user")
            selectedPayer = persons.first(where: { $0.name == meName })
                ?? persons.first(where: { $0.name?.lowercased() == "io" || $0.name?.lowercased() == "me" })
                ?? persons.first
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

        var newExpenseID: UUID?

        if let expense = expenseToEdit {
            expense.amount = value
            expense.note = note
            expense.date = date
            expense.paidBy = payer
            expense.category = selectedCategory.rawValue
            expense.sheet?.lastUpdated = Date()
            expense.splitBetween = NSSet(set: selectedParticipants)

        } else if let sheet = sheet {
            // ➕ ADD
            let expense = Expense(context: viewContext)
            expense.id = UUID()
            newExpenseID = expense.id
            expense.amount = value
            expense.note = note
            expense.date = date
            expense.createdAt = Date()
            expense.sheet = sheet
            expense.paidBy = payer
            expense.category = selectedCategory.rawValue
            expense.splitBetween = NSSet(set: selectedParticipants)

            // Se il foglio è nello shared store, assegna la spesa allo stesso store
            // altrimenti non si sincronizza con gli altri utenti
            if let sheetStore = sheet.objectID.persistentStore {
                viewContext.assign(expense, to: sheetStore)
            }

            sheet.lastUpdated = Date()
        }

        do {
            try viewContext.save()
            // Registra la spesa appena creata come "già nota": non deve
            // generarti una notifica quando il tuo stesso export ri-rientra
            // come import (anche se blocchi il telefono subito dopo).
            if expenseToEdit == nil {
                LastSeenStore.markExpenseKnown(newExpenseID)
            }
            dismiss()
        } catch {
            print("❌ Errore salvataggio spesa:", error)
        }
    }
}
