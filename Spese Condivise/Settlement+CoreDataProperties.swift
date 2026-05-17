import Foundation
import CoreData

extension Settlement: Identifiable {

    @NSManaged public var id: UUID?
    @NSManaged public var date: Date?
    @NSManaged public var note: String?
    @NSManaged public var sheet: SharedSheet?
    @NSManaged public var expenses: NSSet?
    @NSManaged public var balances: NSSet?

    public var expensesArray: [Expense] {
        let set = expenses as? Set<Expense> ?? []
        return set.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    public var balancesArray: [SettlementBalance] {
        let set = balances as? Set<SettlementBalance> ?? []
        return set.sorted { ($0.personName ?? "") < ($1.personName ?? "") }
    }

    public var totalExpensesAmount: Double {
        (expenses as? Set<Expense> ?? []).reduce(0) { $0 + $1.amount }
    }
}
