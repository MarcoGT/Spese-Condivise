import Foundation
import CoreData

extension Expense {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Expense> {
        return NSFetchRequest<Expense>(entityName: "Expense")
    }
    
    @NSManaged public var id: UUID?
    @NSManaged public var amount: Double
    @NSManaged public var note: String?
    @NSManaged public var date: Date?
    @NSManaged public var paidByMe: Bool
    @NSManaged public var sheet: SharedSheet?
    @NSManaged public var archived: Bool
}

extension Expense: Identifiable {}

