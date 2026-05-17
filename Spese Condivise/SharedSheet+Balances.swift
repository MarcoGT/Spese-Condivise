import Foundation

extension SharedSheet {
    
    func balancesPerPerson() -> [Person: Double] {
        var balances: [Person: Double] = [:]
        
        let persons = personsArray
        let expenses = activeExpensesArray
        
        persons.forEach { balances[$0] = 0 }
        
        for expense in expenses {
            guard
                let payer = expense.paidBy,
                let split = expense.splitBetween as? Set<Person>,
                !split.isEmpty
            else { continue }
            
            let share = expense.amount / Double(split.count)
            
                // chi paga anticipa
            balances[payer, default: 0] += expense.amount
            
                // tutti devono la loro quota
            for person in split {
                balances[person, default: 0] -= share
            }
        }
        
        return balances
    }
}

extension SharedSheet {
    
    func balance(for personID: UUID) -> Double {
        guard let me = personsArray.first(where: { $0.id == personID }) else {
            return 0
        }
        
        var balances: [Person: Double] = [:]
        personsArray.forEach { balances[$0] = 0 }
        
        for expense in expensesArray {
            guard
                let payer = expense.paidBy,
                let split = expense.splitBetween as? Set<Person>,
                !split.isEmpty
            else { continue }
            
            let share = expense.amount / Double(split.count)
            balances[payer, default: 0] += expense.amount
            split.forEach { balances[$0, default: 0] -= share }
        }
        
        let value = balances[me] ?? 0
        return abs(value) < 0.005 ? 0 : value
    }
}
