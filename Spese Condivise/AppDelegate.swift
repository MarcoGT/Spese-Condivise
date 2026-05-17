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
        return true
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
        // Push silenzioso CloudKit → aspetta l'import e poi mostra notifica locale
        let persistence = PersistenceController.shared
        remoteNotifObserver = NotificationCenter.default.addObserver(
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

            if let obs = self?.remoteNotifObserver { NotificationCenter.default.removeObserver(obs) }
            self?.remoteNotifObserver = nil
            LastSeenStore.globalLastSeen = Date()
            NotificationService.shared.notifyIfNeeded(context: persistence.container.viewContext)
            completionHandler(.newData)
        }

        // Fallback dopo 20 secondi
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            if let obs = self?.remoteNotifObserver { NotificationCenter.default.removeObserver(obs) }
            self?.remoteNotifObserver = nil
            completionHandler(.noData)
        }
    }

    // Chiamato da iOS quando l'utente accetta un link di condivisione CloudKit.
    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        print("AppDelegate: userDidAcceptCloudKitShareWith")
        let persistenceController = PersistenceController.shared

        persistenceController.executeWhenReady {
            guard let sharedStore = persistenceController.sharedPersistentStore else {
                DispatchQueue.main.async {
                    let msg = NSLocalizedString("share_store_not_found", comment: "Shared store not found error")
                    AppSyncState.current?.pendingShareError = msg
                    NotificationCenter.default.post(name: .shareAcceptanceFailed, object: msg)
                }
                return
            }

            persistenceController.container.acceptShareInvitations(
                from: [cloudKitShareMetadata],
                into: sharedStore
            ) { _, error in
                DispatchQueue.main.async {
                    if let error = error {
                        let msg = error.localizedDescription
                        AppSyncState.current?.pendingShareError = msg
                        NotificationCenter.default.post(name: .shareAcceptanceFailed, object: msg)
                    } else {
                        self.waitForImportThenNotify(persistenceController: persistenceController)
                    }
                }
            }
        }
    }

    // MARK: - Attende import CloudKit dopo accettazione share

    private var remoteNotifObserver: NSObjectProtocol?
    private var importObserver: NSObjectProtocol?
    private var importFallbackWork: DispatchWorkItem?

    // Called from SharedExpensesApp (onOpenURL path) as well as from the
    // userDidAcceptCloudKitShareWith path above.
    func waitForImportThenNotify(persistenceController: PersistenceController) {
        // Cancella eventuali osservatori precedenti
        if let obs = importObserver { NotificationCenter.default.removeObserver(obs) }
        importFallbackWork?.cancel()

        var fired = false

        let notify: () -> Void = { [weak self] in
            guard !fired else { return }
            fired = true
            self?.importObserver = nil
            self?.importFallbackWork = nil

            persistenceController.container.viewContext.refreshAllObjects()
            AppSyncState.current?.pendingShareSuccess = true
            NotificationCenter.default.post(name: .shareAcceptanceSucceeded, object: nil)
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
                event.endDate != nil
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
}
