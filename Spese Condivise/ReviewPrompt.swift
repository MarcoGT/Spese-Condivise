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

    private static let addedExpensesKey = "reviewAddedExpenseCount"
    /// Il pareggio da solo non bastava: molti utenti non ci arrivano mai
    /// (1-2 valutazioni dopo settimane). Queste soglie di spese registrate
    /// indicano che l'app viene usata davvero.
    private static let expenseMilestones: Set<Int> = [10, 30, 75]

    /// Da chiamare dopo un azzeramento saldo andato a buon fine.
    static func afterSettlement() {
        askOncePerVersion()
    }

    /// Da chiamare dopo aver registrato una spesa nuova (non una modifica).
    static func afterExpenseAdded() {
        let defaults = UserDefaults.standard
        let count = defaults.integer(forKey: addedExpensesKey) + 1
        defaults.set(count, forKey: addedExpensesKey)
        if expenseMilestones.contains(count) { askOncePerVersion() }
    }

    /// Al massimo una richiesta per versione dell'app, qualunque sia il motivo.
    private static func askOncePerVersion() {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: promptedVersionKey) != currentVersion else { return }
        defaults.set(currentVersion, forKey: promptedVersionKey)

        // Lascia finire l'animazione (archiviazione o chiusura del modulo): un
        // alert che compare durante la transizione viene chiuso d'istinto.
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
