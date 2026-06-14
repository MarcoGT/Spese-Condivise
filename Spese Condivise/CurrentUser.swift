import Foundation

final class CurrentUser: ObservableObject {

    private static let idKey   = "currentUserPersonID"
    private static let nameKey = "currentUserPersonName"
    private static let mapKey  = "currentUserPersonIDMap"   // [sheetUUID: personUUID]
    private static let kvStore = NSUbiquitousKeyValueStore.default

    @Published private(set) var personID: UUID?
    @Published private(set) var name: String?

    /// Identità per-foglio: per ogni foglio (UUID) memorizza quale Person sei tu.
    /// Necessaria perché ogni foglio ha i propri Person con UUID diversi, quindi
    /// un singolo personID globale non basta per più fogli.
    @Published private(set) var personIDMap: [String: String] = [:]

    init() {
        let storedID = Self.kvStore.string(forKey: Self.idKey)
                    ?? UserDefaults.standard.string(forKey: Self.idKey)
        if let storedID, let id = UUID(uuidString: storedID) {
            personID = id
        }

        let storedName = Self.kvStore.string(forKey: Self.nameKey)
                      ?? UserDefaults.standard.string(forKey: Self.nameKey)
        name = storedName.flatMap { $0.isEmpty ? nil : $0 }

        let storedMap = (Self.kvStore.dictionary(forKey: Self.mapKey) as? [String: String])
                     ?? (UserDefaults.standard.dictionary(forKey: Self.mapKey) as? [String: String])
        personIDMap = storedMap ?? [:]

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

        if keys.contains(Self.mapKey),
           let map = Self.kvStore.dictionary(forKey: Self.mapKey) as? [String: String] {
            DispatchQueue.main.async { self.personIDMap = map }
        }
    }

    // MARK: - Identità per-foglio

    func personID(forSheet sheetID: UUID) -> UUID? {
        guard let stored = personIDMap[sheetID.uuidString] else { return nil }
        return UUID(uuidString: stored)
    }

    func setPersonID(_ id: UUID, forSheet sheetID: UUID) {
        var map = personIDMap
        map[sheetID.uuidString] = id.uuidString
        personIDMap = map
        Self.kvStore.set(map, forKey: Self.mapKey)
        Self.kvStore.synchronize()
        UserDefaults.standard.set(map, forKey: Self.mapKey)

        // Mantieni anche il personID globale allineato all'ultima scelta
        // (retrocompatibilità con eventuale codice legacy).
        if personID != id { setPersonID(id) }
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
        personIDMap = [:]
        Self.kvStore.removeObject(forKey: Self.idKey)
        Self.kvStore.removeObject(forKey: Self.nameKey)
        Self.kvStore.removeObject(forKey: Self.mapKey)
        UserDefaults.standard.removeObject(forKey: Self.idKey)
        UserDefaults.standard.removeObject(forKey: Self.nameKey)
        UserDefaults.standard.removeObject(forKey: Self.mapKey)
    }
}
