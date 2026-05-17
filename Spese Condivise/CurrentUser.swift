import Foundation

final class CurrentUser: ObservableObject {

    private static let key = "currentUserPersonID"

    @Published private(set) var personID: UUID?

    init() {
        // Ripristina l'ID salvato al riavvio dell'app
        if let stored = UserDefaults.standard.string(forKey: Self.key),
           let id = UUID(uuidString: stored) {
            personID = id
        }
    }

    /// Imposta l'ID solo se non è ancora stato impostato, e lo persiste su UserDefaults.
    func bootstrapIfNeeded(with id: UUID) {
        guard personID == nil else { return }
        setPersonID(id)
    }

    /// Sovrascrive sempre l'ID (usato quando identifichiamo con certezza la persona "Io/Me").
    func setPersonID(_ id: UUID) {
        personID = id
        UserDefaults.standard.set(id.uuidString, forKey: Self.key)
    }

    func reset() {
        personID = nil
        UserDefaults.standard.removeObject(forKey: Self.key)
    }
}
