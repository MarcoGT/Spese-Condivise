import Foundation
import CoreData

extension SettlementBalance: Identifiable {

    @NSManaged public var id: UUID?
    @NSManaged public var personName: String?
    @NSManaged public var amount: Double
    @NSManaged public var settlement: Settlement?
}
