import CoreData
import CloudKit

final class PersistenceController: ObservableObject {

    static let shared = PersistenceController()

    let container: NSPersistentCloudKitContainer

    var sharedPersistentStore: NSPersistentStore? {
        return container.persistentStoreCoordinator.persistentStores.first {
            $0.configurationName == "CloudSharing"
        }
    }

    // MARK: - Store readiness

    private var loadedStoreCount = 0
    private var pendingReadyActions: [() -> Void] = []

    // Esegue `block` subito se gli store sono già caricati, altrimenti attende.
    func executeWhenReady(_ block: @escaping () -> Void) {
        DispatchQueue.main.async {
            if self.loadedStoreCount >= 2 {
                block()
            } else {
                self.pendingReadyActions.append(block)
            }
        }
    }

    private func storeDidLoad() {
        loadedStoreCount += 1
        if loadedStoreCount >= 2 {
            let actions = pendingReadyActions
            pendingReadyActions = []
            actions.forEach { $0() }
        }
    }

    private init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "SharedExpenses")
        
        guard let privateStoreDescription = container.persistentStoreDescriptions.first else {
            fatalError("❌ Store description mancante")
        }
        
        let storesURL = privateStoreDescription.url!.deletingLastPathComponent()
        
        if inMemory {
            privateStoreDescription.url = URL(fileURLWithPath: "/dev/null")
        }
        
            // Configurazione Store PRIVATO
        privateStoreDescription.configuration = "Private"
        privateStoreDescription.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: "iCloud.com.marcolagana.SharedExpenses"
        )
        privateStoreDescription.cloudKitContainerOptions?.databaseScope = .private
        
        privateStoreDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        privateStoreDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        
            // Configurazione Store CONDIVISO
        let sharedStoreURL = storesURL.appendingPathComponent("shared.sqlite")
        let sharedStoreDescription = NSPersistentStoreDescription(url: sharedStoreURL)
        sharedStoreDescription.configuration = "CloudSharing"
        
        sharedStoreDescription.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: "iCloud.com.marcolagana.SharedExpenses"
        )
        sharedStoreDescription.cloudKitContainerOptions?.databaseScope = .shared
        
        sharedStoreDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        sharedStoreDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        
            // Assegna entrambe le descrizioni
        container.persistentStoreDescriptions = [privateStoreDescription, sharedStoreDescription]
        
            // Caricamento degli store
        container.loadPersistentStores { (storeDescription, error) in
            if let error = error as NSError? {
                print("❌ Errore caricamento store (\(storeDescription.configuration ?? "N/A")): \(error)")
                fatalError("Unresolved error \(error)")
            } else {
                print("✅ Store caricato: \(storeDescription.configuration ?? "N/A")")
                DispatchQueue.main.async { self.storeDidLoad() }
            }
        }
        
            // Configurazione del contesto
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        do {
            try container.viewContext.setQueryGenerationFrom(.current)
        } catch {
            print("❌ Errore generazione query: \(error)")
        }
    }
}
