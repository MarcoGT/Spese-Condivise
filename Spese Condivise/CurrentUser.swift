import Foundation

final class CurrentUser: ObservableObject {

    private static let idKey   = "currentUserPersonID"
    private static let nameKey = "currentUserPersonName"
    private static let kvStore = NSUbiquitousKeyValueStore.default

    @Published private(set) var personID: UUID?
    @Published private(set) var name: String?

    init() {
        let storedID = Self.kvStore.string(forKey: Self.idKey)
                    ?? UserDefaults.standard.string(forKey: Self.idKey)
        if let storedID, let id = UUID(uuidString: storedID) {
            personID = id
        }

        let storedName = Self.kvStore.string(forKey: Self.nameKey)
                      ?? UserDefaults.standard.string(forKey: Self.nameKey)
        name = storedName.flatMap { $0.isEmpty ? nil : $0 }

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
        ] as? [String] else { return }

        if keys.contains(Self.idKey),
           let stored = Self.kvStore.string(forKey: Self.idKey),
           let id = UUID(uuidString: stored) {
            DispatchQueue.main.async { self.personID = id }
        }

        if keys.contains(Self.nameKey) {
            let n = Self.kvStore.string(forKey: Self.nameKey)
            DispatchQueue.main.async { self.name = n.flatMap { $0.isEmpty ? nil : $0 } }
        }
    }

    func setName(_ newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        name = trimmed.isEmpty ? nil : trimmed
        Self.kvStore.set(trimmed, forKey: Self.nameKey)
        Self.kvStore.synchronize()
        UserDefaults.standard.set(trimmed, forKey: Self.nameKey)
    }

    func bootstrapIfNeeded(with id: UUID) {
        guard personID == nil else { return }
        setPersonID(id)
    }

    func setPersonID(_ id: UUID) {
        personID = id
        Self.kvStore.set(id.uuidString, forKey: Self.idKey)
        Self.kvStore.synchronize()
        UserDefaults.standard.set(id.uuidString, forKey: Self.idKey)
    }

    func reset() {
        personID = nil
        name = nil
        Self.kvStore.removeObject(forKey: Self.idKey)
        Self.kvStore.removeObject(forKey: Self.nameKey)
        UserDefaults.standard.removeObject(forKey: Self.idKey)
        UserDefaults.standard.removeObject(forKey: Self.nameKey)
    }
}
