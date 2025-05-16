import Foundation
import CoreData

extension Person {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Person> {
        NSFetchRequest<Person>(entityName: "Person")
    }
    
    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    
    @NSManaged public var sheet: SharedSheet?
    @NSManaged public var expensesPaid: NSSet?
    @NSManaged public var expensesShared: NSSet?
}

extension Person: Identifiable {}
