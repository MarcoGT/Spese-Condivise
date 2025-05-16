import Foundation
import CoreData

extension SharedSheet: Identifiable {
    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var personName: String?
    @NSManaged public var expenses: NSSet?
    @NSManaged public var currencyCode: String?
    @NSManaged public var lastUpdated: Date?
    
    public var expensesArray: [Expense] {
        let set = expenses as? Set<Expense> ?? []
        return set.sorted { ($0.date ?? Date()) > ($1.date ?? Date()) }
    }
}
