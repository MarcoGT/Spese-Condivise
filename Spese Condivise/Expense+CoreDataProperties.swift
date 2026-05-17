import Foundation
import CoreData

extension Expense {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Expense> {
        NSFetchRequest<Expense>(entityName: "Expense")
    }
    
    @NSManaged public var id: UUID?
    @NSManaged public var amount: Double
    @NSManaged public var note: String?
    @NSManaged public var date: Date?
    @NSManaged public var archived: Bool
    @NSManaged public var category: String?
    @NSManaged public var createdAt: Date?
    
        // RELAZIONI
    @NSManaged public var sheet: SharedSheet?
    @NSManaged public var paidBy: Person?
    @NSManaged public var splitBetween: NSSet?
    @NSManaged public var settlement: Settlement?
}

extension Expense: Identifiable {}
