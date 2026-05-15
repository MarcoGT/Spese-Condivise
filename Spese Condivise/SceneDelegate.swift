import UIKit
import CloudKit

/// Gestisce i callback a livello di UIWindowScene.
/// In app SwiftUI con scene lifecycle, iOS chiama windowScene(_:userDidAcceptCloudKitShareWith:)
/// qui — NON sul UIApplicationDelegate.
class SceneDelegate: NSObject, UIWindowSceneDelegate {

    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {

        let persistenceController = PersistenceController.shared

        persistenceController.executeWhenReady {
            guard let sharedStore = persistenceController.sharedPersistentStore else {
                DispatchQueue.main.async {
                    let msg = NSLocalizedString("share_store_not_found", comment: "")
                    AppSyncState.current?.pendingShareError = msg
                }
                return
            }

            persistenceController.container.acceptShareInvitations(
                from: [cloudKitShareMetadata],
                into: sharedStore
            ) { _, error in
                DispatchQueue.main.async {
                    if let error = error {
                        AppSyncState.current?.pendingShareError = error.localizedDescription
                    } else {
                        // Riusa la stessa logica di AppDelegate
                        AppDelegate.shared?.waitForImportThenNotify(
                            persistenceController: persistenceController
                        )
                    }
                }
            }
        }
    }
}
