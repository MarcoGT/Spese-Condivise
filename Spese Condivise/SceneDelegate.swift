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
        ShareService.acceptInvitation(cloudKitShareMetadata)
    }
}
