import SwiftUI
import CoreData

struct AddSharedSheetView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    @State private var personName = ""
    @State private var selectedCurrency = Locale.current.currency?.identifier ?? "EUR"
    
    let availableCurrencies = ["EUR", "USD", "GBP", "JPY", "CHF", "AUD", "CAD"]
    
    var body: some View {
        NavigationStack {
            Form {
                TextField(NSLocalizedString("sheet name", comment: "sheet name"), text: $name)
                TextField(NSLocalizedString("person name", comment: "person name"), text: $personName)
                Picker("Valuta", selection: $selectedCurrency) {
                    ForEach(availableCurrencies, id: \.self) { code in
                        Text(code)
                    }
                }
            }
            .navigationTitle(NSLocalizedString("new sheet", comment: "new sheet"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("cancel", comment: "cencel"), role: .cancel) {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("save", comment: "save")) {
                        saveSheet()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
    
    private func saveSheet() {
        let sheet = SharedSheet(context: viewContext)
        sheet.id = UUID()
        sheet.name = name
        sheet.personName = personName
        sheet.currencyCode = selectedCurrency
        
        do {
            try viewContext.save()
            dismiss()
        } catch {
            print("❌ Errore salvataggio foglio:", error)
        }
    }
}
