import CoreData
import CloudKit

final class PersistenceController: ObservableObject {
    
    static let shared = PersistenceController()
    
    let container: NSPersistentCloudKitContainer
    
    private init(inMemory: Bool = false) {
        
        container = NSPersistentCloudKitContainer(name: "SharedExpenses")
        
            // MARK: - Private store
        guard let privateStore = container.persistentStoreDescriptions.first else {
            fatalError("❌ Store description mancante")
        }
        
        if inMemory {
            privateStore.url = URL(fileURLWithPath: "/dev/null")
        }
        
        privateStore.cloudKitContainerOptions =
        NSPersistentCloudKitContainerOptions(
            containerIdentifier: "iCloud.com.marcolagana.SharedExpenses"
        )
        
        privateStore.setOption(true as NSNumber,
                               forKey: NSPersistentHistoryTrackingKey)
        privateStore.setOption(true as NSNumber,
                               forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        
            // MARK: - Shared store (CRITICO: prima del load)
        let sharedStore = NSPersistentStoreDescription()
        //sharedStore.configuration = "CloudSharing"
        sharedStore.cloudKitContainerOptions =
        NSPersistentCloudKitContainerOptions(
            containerIdentifier: "iCloud.com.marcolagana.SharedExpenses"
        )
        sharedStore.cloudKitContainerOptions?.databaseScope = .shared
        
        sharedStore.setOption(true as NSNumber,
                              forKey: NSPersistentHistoryTrackingKey)
        sharedStore.setOption(true as NSNumber,
                              forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        
        container.persistentStoreDescriptions.append(sharedStore)
        
            // MARK: - Load stores
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("❌ Errore Core Data: \(error)")
            }
        }
        
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
}

