#if DEBUG
import CoreData

/// Dati finti per gli screenshot dell'App Store. Attivi solo in build di debug
/// lanciate con `-demoData`, su uno store temporaneo scollegato da CloudKit
/// (vedi PersistenceController): non toccano mai i dati veri né iCloud.
/// La lingua segue quella del simulatore, per avere screenshot it e en.
enum DemoData {

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-demoData")
    }

    /// Schermata da aprire all'avvio per lo screenshot: `-demoScreen detail|add|stats`.
    static var screen: String? {
        isEnabled ? UserDefaults.standard.string(forKey: "demoScreen") : nil
    }

    static var italianUI: Bool {
        Locale.preferredLanguages.first?.hasPrefix("it") ?? false
    }

    private struct Spesa {
        let note: String
        let amount: Double
        let payer: Int
        let category: ExpenseCategory
        let daysAgo: Int
        var split: [Int]? = nil
    }

    private struct Foglio {
        let name: String
        let emoji: String
        let color: String
        let people: [String]
        let hoursAgo: Double
        let expenses: [Spesa]
    }

    // L'indice 0 di `people` è sempre l'utente (passato con -currentUserPersonName).
    private static let italian: [Foglio] = [
        Foglio(name: "Weekend a Lisbona", emoji: "✈️", color: "blue",
               people: ["Marco", "Giulia", "Luca", "Sara"], hoursAgo: 1, expenses: [
            Spesa(note: "Voli andata e ritorno", amount: 412.80, payer: 0, category: .transport, daysAgo: 6),
            Spesa(note: "Appartamento in Alfama", amount: 360.00, payer: 1, category: .accommodation, daysAgo: 5),
            Spesa(note: "Cena al Bairro Alto", amount: 96.40, payer: 2, category: .food, daysAgo: 4),
            Spesa(note: "Tram 28 e metro", amount: 24.00, payer: 3, category: .transport, daysAgo: 4),
            Spesa(note: "Museo degli Azulejos", amount: 44.00, payer: 1, category: .entertainment, daysAgo: 3),
            Spesa(note: "Pastéis de nata", amount: 12.60, payer: 0, category: .food, daysAgo: 3),
        ]),
        Foglio(name: "Casa via Roma", emoji: "🏠", color: "orange",
               people: ["Marco", "Andrea", "Chiara"], hoursAgo: 20, expenses: [
            Spesa(note: "Bolletta luce", amount: 86.30, payer: 1, category: .utilities, daysAgo: 12),
            Spesa(note: "Spesa settimanale", amount: 64.20, payer: 2, category: .shopping, daysAgo: 9),
            Spesa(note: "Internet fibra", amount: 29.90, payer: 0, category: .utilities, daysAgo: 8),
            Spesa(note: "Detersivi", amount: 18.50, payer: 2, category: .shopping, daysAgo: 5),
            Spesa(note: "Spesa settimanale", amount: 71.40, payer: 1, category: .shopping, daysAgo: 2),
        ]),
        Foglio(name: "Cena di compleanno", emoji: "🎂", color: "pink",
               people: ["Marco", "Luca", "Sara", "Paolo", "Giulia"], hoursAgo: 50, expenses: [
            Spesa(note: "Ristorante", amount: 186.50, payer: 0, category: .food, daysAgo: 15),
            Spesa(note: "Torta", amount: 32.00, payer: 2, category: .food, daysAgo: 15),
        ]),
        Foglio(name: "Weekend in montagna", emoji: "🏔️", color: "teal",
               people: ["Marco", "Paolo"], hoursAgo: 200, expenses: [
            Spesa(note: "Rifugio", amount: 120.00, payer: 0, category: .accommodation, daysAgo: 30),
            Spesa(note: "Skipass", amount: 120.00, payer: 1, category: .entertainment, daysAgo: 30),
        ]),
    ]

    private static let english: [Foglio] = [
        Foglio(name: "Weekend in Lisbon", emoji: "✈️", color: "blue",
               people: ["Alex", "Emma", "Liam", "Sofia"], hoursAgo: 1, expenses: [
            Spesa(note: "Return flights", amount: 412.80, payer: 0, category: .transport, daysAgo: 6),
            Spesa(note: "Apartment in Alfama", amount: 360.00, payer: 1, category: .accommodation, daysAgo: 5),
            Spesa(note: "Dinner in Bairro Alto", amount: 96.40, payer: 2, category: .food, daysAgo: 4),
            Spesa(note: "Tram 28 and metro", amount: 24.00, payer: 3, category: .transport, daysAgo: 4),
            Spesa(note: "Tile Museum", amount: 44.00, payer: 1, category: .entertainment, daysAgo: 3),
            Spesa(note: "Pastéis de nata", amount: 12.60, payer: 0, category: .food, daysAgo: 3),
        ]),
        Foglio(name: "Flat on Rose Street", emoji: "🏠", color: "orange",
               people: ["Alex", "Noah", "Mia"], hoursAgo: 20, expenses: [
            Spesa(note: "Electricity bill", amount: 86.30, payer: 1, category: .utilities, daysAgo: 12),
            Spesa(note: "Weekly groceries", amount: 64.20, payer: 2, category: .shopping, daysAgo: 9),
            Spesa(note: "Broadband", amount: 29.90, payer: 0, category: .utilities, daysAgo: 8),
            Spesa(note: "Cleaning supplies", amount: 18.50, payer: 2, category: .shopping, daysAgo: 5),
            Spesa(note: "Weekly groceries", amount: 71.40, payer: 1, category: .shopping, daysAgo: 2),
        ]),
        Foglio(name: "Birthday dinner", emoji: "🎂", color: "pink",
               people: ["Alex", "Liam", "Sofia", "Noah", "Emma"], hoursAgo: 50, expenses: [
            Spesa(note: "Restaurant", amount: 186.50, payer: 0, category: .food, daysAgo: 15),
            Spesa(note: "Cake", amount: 32.00, payer: 2, category: .food, daysAgo: 15),
        ]),
        Foglio(name: "Mountain weekend", emoji: "🏔️", color: "teal",
               people: ["Alex", "Noah"], hoursAgo: 200, expenses: [
            Spesa(note: "Mountain hut", amount: 120.00, payer: 0, category: .accommodation, daysAgo: 30),
            Spesa(note: "Ski pass", amount: 120.00, payer: 1, category: .entertainment, daysAgo: 30),
        ]),
    ]

    static func seed(into context: NSManagedObjectContext) {
        let currency = "EUR"
        let now = Date()
        var appearance: [(SharedSheet, String, String)] = []

        for f in italianUI ? italian : english {
            let sheet = SharedSheet(context: context)
            sheet.id = UUID()
            sheet.name = f.name
            sheet.currencyCode = currency
            sheet.lastUpdated = now.addingTimeInterval(-f.hoursAgo * 3600)

            let persons: [Person] = f.people.map { name in
                let p = Person(context: context)
                p.id = UUID()
                p.name = name
                p.sheet = sheet
                return p
            }

            for s in f.expenses {
                let e = Expense(context: context)
                e.id = UUID()
                e.note = s.note
                e.amount = s.amount
                e.category = s.category.rawValue
                e.date = now.addingTimeInterval(-Double(s.daysAgo) * 86400)
                e.createdAt = e.date
                e.archived = false
                e.sheet = sheet
                e.paidBy = persons[s.payer]
                e.splitBetween = NSSet(array: (s.split ?? Array(persons.indices)).map { persons[$0] })
            }
            appearance.append((sheet, f.emoji, f.color))
        }

        try? context.save()

        // Dopo il save: le chiavi di emoji/colore usano l'objectID definitivo.
        for (sheet, emoji, color) in appearance {
            SheetAppearanceStore.shared.setEmoji(emoji, for: sheet)
            SheetAppearanceStore.shared.setColor(named: color, for: sheet)
            // Niente pallino "spese nuove": in uno screenshot sembrerebbero arretrati.
            LastSeenStore.markSeen(for: sheet)
        }

        if UserDefaults.standard.bool(forKey: "demoExportPDF") {
            exportPDFs(context: context, sheets: appearance.map(\.0))
        }
    }

    /// `-demoExportPDF YES`: scrive i PDF dei fogli demo nella tmp dell'app, più
    /// un foglio lungo per verificare cambio pagina e descrizioni troncate.
    private static func exportPDFs(context: NSManagedObjectContext, sheets: [SharedSheet]) {
        let long = SharedSheet(context: context)
        long.id = UUID()
        long.name = "Test PDF lungo"
        long.currencyCode = "EUR"
        let people = ["Marco", "Giorgia", "Reno", "Rosy"].map { name -> Person in
            let p = Person(context: context); p.id = UUID(); p.name = name; p.sheet = long; return p
        }
        let notes = ["Autostrada Lindau", "Benzina", "Cena in trattoria con vista sul lago e dolce della casa",
                     "Parcheggio", "Colazione", "Traghetto per Bregenz andata e ritorno con biglietti per tutti e quattro più supplemento bagagli e bici",
                     "Supermercato", "Museo", "Gelato"]
        let cats: [ExpenseCategory] = [.transport, .transport, .food, .transport, .food, .transport, .shopping, .entertainment, .food]
        for i in 0..<45 {
            let e = Expense(context: context)
            e.id = UUID(); e.sheet = long; e.archived = false
            e.note = notes[i % notes.count]
            e.category = cats[i % cats.count].rawValue
            e.amount = Double((i * 37) % 180) + 4.5
            e.date = Date().addingTimeInterval(-Double(i) * 3600 * 9)
            e.createdAt = e.date
            e.paidBy = people[i % people.count]
            e.splitBetween = NSSet(array: people)
        }
        try? context.save()
        for sheet in sheets + [long] {
            print("DEMO_PDF:", PDFExporter.generate(for: sheet).path)
        }
    }
}
#endif
