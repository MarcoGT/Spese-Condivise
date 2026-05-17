import Foundation
import CoreData

enum SettlementService {

    /// Archivia tutte le spese attive del foglio e crea un record Settlement
    /// con lo snapshot dei saldi al momento dell'azzeramento.
    static func performSettlement(sheet: SharedSheet, context: NSManagedObjectContext) throws {
        let activeExpenses = sheet.activeExpensesArray
        guard !activeExpenses.isEmpty else { return }

        // 1. Calcola i saldi correnti (solo spese attive)
        let balances = computeBalances(expenses: activeExpenses, persons: sheet.personsArray)

        // 2. Crea il Settlement
        let settlement = Settlement(context: context)
        settlement.id = UUID()
        settlement.date = Date()
        settlement.sheet = sheet

        // 3. Snapshot dei saldi per ogni persona
        for (person, amount) in balances {
            let entry = SettlementBalance(context: context)
            entry.id = UUID()
            entry.personName = person.name
            entry.amount = amount
            entry.settlement = settlement
        }

        // 4. Archivia le spese attive e collegale al settlement
        for expense in activeExpenses {
            expense.archived = true
            expense.settlement = settlement
        }

        // 5. Aggiorna il timestamp del foglio
        sheet.lastUpdated = Date()

        // 6. Salva
        try context.save()
    }

    // MARK: - Private

    private static func computeBalances(
        expenses: [Expense],
        persons: [Person]
    ) -> [Person: Double] {
        var balances: [Person: Double] = [:]
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
}
