import Foundation
import CoreData

extension SharedSheet: Identifiable {
    
    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var currencyCode: String?
    @NSManaged public var lastUpdated: Date?
    
        // RELAZIONI
    @NSManaged public var expenses: NSSet?
    @NSManaged public var persons: NSSet?
    @NSManaged public var settlements: NSSet?

    // MARK: - Computed helpers

    /// Tutte le spese (attive + archiviate)
    public var expensesArray: [Expense] {
        let set = expenses as? Set<Expense> ?? []
        return set.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    /// Solo le spese attive (non archiviate) — usare per calcoli saldo e UI principale
    public var activeExpensesArray: [Expense] {
        let set = expenses as? Set<Expense> ?? []
        return set
            .filter { !$0.archived }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    public var personsArray: [Person] {
        let set = persons as? Set<Person> ?? []
        return set.sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    public var settlementsArray: [Settlement] {
        let set = settlements as? Set<Settlement> ?? []
        return set.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }
}
