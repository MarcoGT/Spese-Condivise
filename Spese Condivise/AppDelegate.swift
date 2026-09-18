import UIKit
import CloudKit
import CoreData

// Notifiche per comunicare l'esito dell'accettazione share alla UI
extension Notification.Name {
    static let shareAcceptanceSucceeded = Notification.Name("shareAcceptanceSucceeded")
    static let shareAcceptanceFailed    = Notification.Name("shareAcceptanceFailed")
}

class AppDelegate: NSObject, UIApplicationDelegate {

    // Riferimento statico per SceneDelegate
    static weak var shared: AppDelegate?

    // Registra l'app per le notifiche remote di CloudKit.
    // Senza questo, NSPersistentCloudKitContainer non riceve push CloudKit
    // e il database condiviso non si sincronizza automaticamente.
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        AppDelegate.shared = self
        application.registerForRemoteNotifications()

        // Al primo avvio fissa il watermark a "ora": evita di notificare le
        // spese già esistenti durante la prima sincronizzazione.
        if UserDefaults.standard.object(forKey: "globalLastSeen") == nil {
            LastSeenStore.globalLastSeen = Date()
        }

        // Observer sempre attivo: a ogni import CloudKit completato valuta se
        // mostrare una notifica locale. È più affidabile del solo handler della
        // push (che dipende dal timing); il watermark in notifyIfNeeded evita
        // notifiche duplicate quando entrambi i percorsi scattano.
        startImportNotificationObserver()
        return true
    }

    private var importNotifyObserver: NSObjectProtocol?

    private func startImportNotificationObserver() {
        importNotifyObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard
                let event = notification.userInfo?[
                    NSPersistentCloudKitContainer.eventNotificationUserInfoKey
                ] as? NSPersistentCloudKitContainer.Event,
                event.type == .import,
                event.endDate != nil,
                event.error == nil
            else { return }

            NotificationService.shared.notifyIfNeeded(
                context: PersistenceController.shared.container.viewContext
            )
        }
    }

    // Collega SceneDelegate alla finestra SwiftUI (necessario per ricevere
    // windowScene(_:userDidAcceptCloudKitShareWith:))
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // Push silenzioso CloudKit → aspetta l'import e poi mostra notifica locale.
        //
        // IMPORTANTE: il completionHandler deve essere chiamato ESATTAMENTE una volta.
        // Una doppia chiamata fa crashare l'app con dispatch_group_leave underflow
        // (EXC_BREAKPOINT in libdispatch). Per questo ogni invocazione usa il proprio
        // stato locale (observer + flag `fired`) invece di una proprietà condivisa,
        // che con più push ravvicinate veniva sovrascritta causando doppie chiamate.
        let persistence = PersistenceController.shared

        // Contenitore reference-type: le closure @Sendable non possono mutare
        // var locali catturate (warning Swift 6), quindi lo stato per-invocazione
        // vive in una piccola classe condivisa tra observer e fallback.
        final class State {
            var observer: NSObjectProtocol?
            var fired = false
        }
        let state = State()

        // Chiamato sia dall'evento di import sia dal fallback: garantisce
        // una sola chiamata al completionHandler e una sola rimozione dell'observer.
        let finish: (UIBackgroundFetchResult) -> Void = { result in
            guard !state.fired else { return }
            state.fired = true
            if let obs = state.observer {
                NotificationCenter.default.removeObserver(obs)
                state.observer = nil
            }
            completionHandler(result)
        }

        state.observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard
                let event = notification.userInfo?[
                    NSPersistentCloudKitContainer.eventNotificationUserInfoKey
                ] as? NSPersistentCloudKitContainer.Event,
                event.type == .import,
                event.endDate != nil,
                event.error == nil
            else { return }

            // notifyIfNeeded legge il watermark precedente, mostra la notifica
            // per le spese nuove e poi aggiorna il watermark internamente.
            // NON impostare globalLastSeen qui: lo farebbe avanzare prima della
            // query, facendo sparire le spese appena importate.
            NotificationService.shared.notifyIfNeeded(context: persistence.container.viewContext)
            finish(.newData)
        }

        // Fallback dopo 20 secondi (no-op se l'import è già arrivato)
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
            finish(.noData)
        }
    }

    // Chiamato da iOS quando l'utente accetta un link di condivisione CloudKit.
    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        ShareService.acceptInvitation(cloudKitShareMetadata)
    }

    // MARK: - Attende import CloudKit dopo accettazione share

    private var importObserver: NSObjectProtocol?
    private var importFallbackWork: DispatchWorkItem?

    // Called from SharedExpensesApp (onOpenURL path) as well as from the
    // userDidAcceptCloudKitShareWith path above.
    func waitForImportThenNotify(persistenceController: PersistenceController) {
        // Cancella eventuali osservatori precedenti
        if let obs = importObserver { NotificationCenter.default.removeObserver(obs) }
        importFallbackWork?.cancel()

        // Da qui in poi la lista deve restare in attesa del foglio: il segnale
        // di "accettata" arriva molto prima dei record veri (CloudKit scarica
        // la zona condivisa in un secondo momento).
        AppSyncState.current.isSyncingSharedSheet = true

        var fired = false

        let notify: () -> Void = { [weak self] in
            guard !fired else { return }
            fired = true
            self?.importObserver = nil
            self?.importFallbackWork = nil

            persistenceController.container.viewContext.refreshAllObjects()
            // Le spese già presenti nel foglio appena accettato non devono
            // generare notifiche: registrale tutte come già note.
            LastSeenStore.seedAllKnown(context: persistenceController.container.viewContext)
            AppSyncState.current.pendingShareSuccess = true
            NotificationCenter.default.post(name: .shareAcceptanceSucceeded, object: nil)

            // L'import che ci ha svegliato può essere quello dello store privato:
            // continua a rinfrescare per far comparire il foglio quando la zona
            // condivisa finisce di scaricarsi.
            self?.startPostAcceptRefresh(persistenceController: persistenceController)
        }

        // Ascolta l'evento di import di NSPersistentCloudKitContainer
        importObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let event = notification.userInfo?[
                    NSPersistentCloudKitContainer.eventNotificationUserInfoKey
                ] as? NSPersistentCloudKitContainer.Event,
                event.type == .import,
                event.endDate != nil,
                event.error == nil
            else { return }

            if let obs = self?.importObserver {
                NotificationCenter.default.removeObserver(obs)
            }
            notify()
        }

        // Fallback: dopo 20 secondi notifichiamo comunque (i dati arriveranno
        // con il prossimo sync push di CloudKit)
        let work = DispatchWorkItem { notify() }
        importFallbackWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: work)

        // Richiedi subito un refresh per innescare il ciclo di sync
        persistenceController.container.viewContext.refreshAllObjects()
    }

    private var postAcceptRefreshWork: DispatchWorkItem?

    /// Rinfresca il viewContext ogni 3s per 2 minuti dopo l'accettazione di una
    /// share. Serve perché l'arrivo dei record della zona condivisa non sempre
    /// genera un remote-change che la lista riesce a intercettare in tempo.
    private func startPostAcceptRefresh(persistenceController: PersistenceController) {
        postAcceptRefreshWork?.cancel()

        let context = persistenceController.container.viewContext
        var ticks = 0
        var schedule: (() -> Void)!
        schedule = {
            let work = DispatchWorkItem {
                ticks += 1
                context.refreshAllObjects()
                if ticks >= 40 {
                    AppSyncState.current.isSyncingSharedSheet = false
                } else if AppSyncState.current.isSyncingSharedSheet {
                    schedule()
                }
            }
            self.postAcceptRefreshWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
        }
        schedule()
    }

}
