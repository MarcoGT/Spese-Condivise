import SwiftUI
import CloudKit
import UIKit

struct CloudSharingView: UIViewControllerRepresentable {
    
    let share: CKShare
    let container: CKContainer
    
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(
            share: share,
            container: container
        )
        controller.delegate = context.coordinator
        
            // AGGIUNGI QUESTE RIGHE:
        controller.availablePermissions = [.allowPublic, .allowReadOnly, .allowPrivate]
        
        controller.modalPresentationStyle = .formSheet
        return controller
    }
    
    func updateUIViewController(
        _ uiViewController: UICloudSharingController,
        context: Context
    ) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss)
    }
    
    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        
        let dismiss: DismissAction
        
        init(dismiss: DismissAction) {
            self.dismiss = dismiss
        }
        
        func cloudSharingControllerDidFinishSharing(
            _ csc: UICloudSharingController
        ) {
            dismiss()
        }
        
        func cloudSharingController(
            _ csc: UICloudSharingController,
            failedToSaveShareWithError error: Error
        ) {
            print("❌ Cloud sharing error: \(error)")
        }
        
        func itemTitle(
            for csc: UICloudSharingController
        ) -> String? {
            NSLocalizedString("shared sheet", comment: "shared sheet")
        }
    }
}

