import Foundation

final class CurrentUser: ObservableObject {
    
    @Published private(set) var personID: UUID?
    
        // ✅ unico punto dove può essere impostato
    func bootstrapIfNeeded(with id: UUID) {
        guard personID == nil else { return }
        personID = id
    }
    
        // opzionale, ma utile in futuro
    func reset() {
        personID = nil
    }
}
