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
    
        // MARK: - Computed helpers
    
    public var expensesArray: [Expense] {
        let set = expenses as? Set<Expense> ?? []
        return set.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }
    
    public var personsArray: [Person] {
        let set = persons as? Set<Person> ?? []
        return set.sorted { ($0.name ?? "") < ($1.name ?? "") }
    }
}
