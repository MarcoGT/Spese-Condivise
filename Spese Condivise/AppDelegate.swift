import UIKit
import CloudKit

class AppDelegate: NSObject, UIApplicationDelegate {

    // Metodo chiamato da iOS quando l'utente tocca un link di condivisione CloudKit.
    // Senza questo, iOS non sa come consegnare l'invito all'app.
    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        let persistenceController = PersistenceController.shared
        // Gli store si caricano in modo asincrono: attendiamo che siano pronti
        // prima di chiamare acceptShareInvitations, altrimenti sharedPersistentStore è nil.
        persistenceController.executeWhenReady {
            guard let sharedStore = persistenceController.sharedPersistentStore else {
                print("❌ Shared persistent store non trovato")
                return
            }
            persistenceController.container.acceptShareInvitations(
                from: [cloudKitShareMetadata],
                into: sharedStore
            ) { _, error in
                if let error = error {
                    print("❌ Errore accettazione condivisione: \(error.localizedDescription)")
                } else {
                    print("✅ Condivisione accettata tramite AppDelegate")
                }
            }
        }
    }
}
