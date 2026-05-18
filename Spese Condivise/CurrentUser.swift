import Foundation

final class CurrentUser: ObservableObject {

    private static let key = "currentUserPersonID"
    private static let kvStore = NSUbiquitousKeyValueStore.default

    @Published private(set) var personID: UUID?

    init() {
        // Legge prima da iCloud KV store, poi da UserDefaults come fallback
        let stored = Self.kvStore.string(forKey: Self.key)
                  ?? UserDefaults.standard.string(forKey: Self.key)
        if let stored, let id = UUID(uuidString: stored) {
            personID = id
        }

        // Osserva aggiornamenti iCloud (es. cambio da un altro dispositivo)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(kvStoreDidChange),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: Self.kvStore
        )
        Self.kvStore.synchronize()
    }

    @objc private func kvStoreDidChange(_ notification: Notification) {
        guard let keys = notification.userInfo?[
            NSUbiquitousKeyValueStoreChangedKeysKey
        ] as? [String], keys.contains(Self.key) else { return }

        if let stored = Self.kvStore.string(forKey: Self.key),
           let id = UUID(uuidString: stored) {
            DispatchQueue.main.async { self.personID = id }
        }
    }

    /// Imposta l'ID solo se non è ancora stato impostato.
    func bootstrapIfNeeded(with id: UUID) {
        guard personID == nil else { return }
        setPersonID(id)
    }

    /// Sovrascrive sempre l'ID — sincronizzato su tutti i dispositivi iCloud.
    func setPersonID(_ id: UUID) {
        personID = id
        Self.kvStore.set(id.uuidString, forKey: Self.key)
        Self.kvStore.synchronize()
        UserDefaults.standard.set(id.uuidString, forKey: Self.key) // fallback offline
    }

    func reset() {
        personID = nil
        Self.kvStore.removeObject(forKey: Self.key)
        UserDefaults.standard.removeObject(forKey: Self.key)
    }
}
