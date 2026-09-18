import StoreKit
import UIKit

/// Richiesta di recensione all'App Store.
///
/// Va chiesta nel momento in cui l'app ha appena dimostrato il proprio valore
/// — subito dopo un pareggio dei conti riuscito — e mai all'avvio o dopo un
/// errore. iOS concede al massimo 3 richieste per anno e le consuma anche
/// quando l'utente le ignora: chiederle nel momento sbagliato le brucia.
enum ReviewPrompt {

    private static let promptedVersionKey = "reviewPromptedVersion"

    private static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    /// Da chiamare dopo un azzeramento saldo andato a buon fine.
    /// Al massimo una richiesta per versione dell'app.
    static func afterSettlement() {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: promptedVersionKey) != currentVersion else { return }
        defaults.set(currentVersion, forKey: promptedVersionKey)

        // Lascia finire l'animazione di archiviazione delle spese: un alert che
        // compare durante la transizione viene chiuso d'istinto.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            ask()
        }
    }

    @MainActor
    private static func ask() {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else { return }

        if #available(iOS 18.0, *) {
            AppStore.requestReview(in: scene)
        } else {
            SKStoreReviewController.requestReview(in: scene)
        }
    }
}
