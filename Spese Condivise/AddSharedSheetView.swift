import SwiftUI
import CoreData

struct AddSharedSheetView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var currentUser: CurrentUser
    
    @State private var name = ""
    @State private var selectedCurrency = Locale.current.currency?.identifier ?? "EUR"
    
    let availableCurrencies = ["EUR", "USD", "GBP", "JPY", "CHF", "AUD", "CAD"]
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        NSLocalizedString("sheet name", comment: ""),
                        text: $name
                    )
                }
                
                Section {
                    Picker(NSLocalizedString("currency", comment: ""), selection: $selectedCurrency) {
                        ForEach(availableCurrencies, id: \.self) { code in
                            Text(code)
                        }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("new sheet", comment: ""))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("cancel", comment: ""), role: .cancel) {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("save", comment: "")) {
                        saveSheet()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
    
    private func saveSheet() {
        let sheet = SharedSheet(context: viewContext)
        sheet.id = UUID()
        sheet.name = name.trimmingCharacters(in: .whitespaces)
        sheet.currencyCode = selectedCurrency
        sheet.lastUpdated = Date()
        
            // 👤 CREA SOLO IL PROPRIETARIO (UTENTE CORRENTE)
        let me = Person(context: viewContext)
        me.id = UUID()
        me.name = currentUser.name ?? NSLocalizedString("Me", comment: "current user")
        me.sheet = sheet
        
            // 🔐 sei tu il creatore: registra l'identità per QUESTO foglio
        if let sid = sheet.id, let mid = me.id {
            currentUser.setPersonID(mid, forSheet: sid)
        }
        
        do {
            try viewContext.save()

            // 🔗 Pre-crea la CKShare SUBITO, in background: sull'oggetto appena
            // salvato (non ancora esportato) CloudKit lo colloca direttamente
            // nella zona condivisibile. Al tap su "condividi" la share esiste
            // già → link istantaneo, niente spostamento di zona che si impalla.
            ShareService.ensureShare(for: sheet.objectID)

            dismiss()
        } catch {
            print("❌ Errore salvataggio foglio:", error)
        }
    }
}
