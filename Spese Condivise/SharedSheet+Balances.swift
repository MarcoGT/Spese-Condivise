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

    /// Risolve quale Person sei tu in QUESTO foglio, in ordine di affidabilità:
    /// 1. identità per-foglio salvata esplicitamente
    /// 2. corrispondenza per nome utente
    /// 3. legacy: personID globale, se presente in questo foglio
    /// 4. legacy: persona chiamata "Io"/"Me"
    func resolvedMyPerson(using user: CurrentUser) -> Person? {
        if let sid = id, let pid = user.personID(forSheet: sid),
           let match = personsArray.first(where: { $0.id == pid }) {
            return match
        }
        if let myName = user.name?.lowercased(),
           let match = personsArray.first(where: { $0.name?.lowercased() == myName }) {
            return match
        }
        if let gid = user.personID,
           let match = personsArray.first(where: { $0.id == gid }) {
            return match
        }
        let me = NSLocalizedString("Me", comment: "").lowercased()
        return personsArray.first {
            $0.name?.lowercased() == "io" || $0.name?.lowercased() == me
        }
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
