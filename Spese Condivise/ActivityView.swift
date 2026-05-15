import SwiftUI
import UIKit

struct ActivityView: UIViewControllerRepresentable {

    let activityItems: [Any]
    var onComplete: (() -> Void)? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )

        vc.popoverPresentationController?.sourceView =
            UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                .first

        // Chiude il foglio SwiftUI automaticamente dopo che l'utente
        // ha condiviso (o annullato) dall'activity controller
        vc.completionWithItemsHandler = { _, _, _, _ in
            onComplete?()
        }

        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
