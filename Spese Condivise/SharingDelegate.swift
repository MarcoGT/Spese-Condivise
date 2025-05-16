import UIKit
import CloudKit

    /// Delegate minimale per CloudKit Sharing.
    /// NON presenta UI, NON genera link manuali.
final class SharingDelegate: NSObject, UICloudSharingControllerDelegate {

    static let shared = SharingDelegate()
    
    func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
        print("✅ Condivisione CloudKit salvata correttamente")
    }
    
    func cloudSharingController(
        _ csc: UICloudSharingController,
        failedToSaveShareWithError error: Error
    ) {
        print("❌ Errore salvataggio condivisione: \(error.localizedDescription)")
    }
    
    func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
        print("ℹ️ Condivisione interrotta")
    }
    
    func itemTitle(for csc: UICloudSharingController) -> String? {
        NSLocalizedString("Foglio condiviso", comment: "")
    }
}

