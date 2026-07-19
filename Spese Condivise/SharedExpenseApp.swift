import SwiftUI
import CloudKit
import CoreData

extension Notification.Name {
    static let macMenuSettings  = Notification.Name("macMenuSettings")
}

// MARK: - Focused values per comandi context-sensitive

private struct NewActionKey: FocusedValueKey {
    typealias Value = () -> Void
}
private struct ExportActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var newAction: (() -> Void)? {
        get { self[NewActionKey.self] }
        set { self[NewActionKey.self] = newValue }
    }
    var exportAction: (() -> Void)? {
        get { self[ExportActionKey.self] }
        set { self[ExportActionKey.self] = newValue }
    }
}

private struct NewCommandButton: View {
    @FocusedValue(\.newAction) var newAction
    var body: some View {
        Button(NSLocalizedString("menu_new", comment: "")) { newAction?() }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(newAction == nil)
    }
}

private struct ExportCommandButton: View {
    @FocusedValue(\.exportAction) var exportAction
    var body: some View {
        Button(NSLocalizedString("menu_export_pdf", comment: "")) { exportAction?() }
            .keyboardShortcut("p", modifiers: .command)
            .disabled(exportAction == nil)
    }
}

@main
struct SharedExpensesApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    let persistenceController = PersistenceController.shared
    private let cloudContainer = CKContainer(identifier: "iCloud.com.marcolagana.SharedExpenses")
    @StateObject private var syncState = AppSyncState()
    @StateObject private var currentUser = CurrentUser()
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    var body: some Scene {
        WindowGroup {
            SharedSheetListView()
                .environment(\.managedObjectContext,
                              persistenceController.container.viewContext)
                .environmentObject(persistenceController)
                .environmentObject(syncState)
                .environmentObject(currentUser)
                .fullScreenCover(isPresented: .init(
                    get: { !hasSeenOnboarding },
                    set: { if !$0 { hasSeenOnboarding = true } }
                )) {
                    OnboardingView(isPresented: .init(
                        get: { !hasSeenOnboarding },
                        set: { if !$0 { hasSeenOnboarding = true } }
                    ))
                }
                .fullScreenCover(isPresented: .init(
                    get: { hasSeenOnboarding && currentUser.name == nil },
                    set: { _ in }
                )) {
                    NameSetupView()
                        .environmentObject(currentUser)
                }
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
                    if let url = userActivity.webpageURL {
                        handleIncomingURL(url)
                    }
                }
                .onAppear {
                    // Registra l'istanza live per AppDelegate (no SwiftUI environment)
                    AppSyncState.current = syncState
                    prewarmCloudKit()
                    observeCloudKitSync()
                    NotificationService.shared.requestPermission()
                    NotificationService.shared.setupSubscriptions()
                }
        }
        #if targetEnvironment(macCatalyst)
        .commands {
            CommandGroup(replacing: .newItem) {
                NewCommandButton()
            }
            CommandGroup(replacing: .appSettings) {
                Button(NSLocalizedString("menu_settings", comment: "")) {
                    NotificationCenter.default.post(name: .macMenuSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
CommandGroup(replacing: .printItem) {
                ExportCommandButton()
            }
        }
        #endif
    }

    // MARK: - CloudKit sync observer

    private func observeCloudKitSync() {
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: persistenceController.container.persistentStoreCoordinator,
            queue: .main
        ) { _ in
            persistenceController.container.viewContext.refreshAllObjects()
        }
    }

    private func prewarmCloudKit() {
        let context = persistenceController.container.viewContext
        context.perform {
            let request = NSFetchRequest<NSFetchRequestResult>(entityName: "SharedSheet")
            request.fetchLimit = 1
            _ = try? context.fetch(request)
        }
    }

    // MARK: - CloudKit Sharing (onOpenURL path)

    private func handleIncomingURL(_ url: URL) {
        if url.absoluteString.contains("icloud.com") && url.absoluteString.contains("share") {
            handleCloudKitShare(url: url)
        }
    }

    private func handleCloudKitShare(url: URL) {
        cloudContainer.fetchShareMetadata(with: url) { (metadata, error) in
            if let error = error {
                DispatchQueue.main.async {
                    let msg = self.sharingErrorMessage(for: error)
                    AppSyncState.current?.pendingShareError = msg
                    NotificationCenter.default.post(name: .shareAcceptanceFailed, object: msg)
                }
                return
            }

            guard let metadata = metadata else {
                DispatchQueue.main.async {
                    let msg = NSLocalizedString("share_unknown_error", comment: "Unknown share error")
                    AppSyncState.current?.pendingShareError = msg
                    NotificationCenter.default.post(name: .shareAcceptanceFailed, object: msg)
                }
                return
            }

            PersistenceController.shared.executeWhenReady {
                guard let sharedStore = PersistenceController.shared.sharedPersistentStore else {
                    DispatchQueue.main.async {
                        let msg = NSLocalizedString("share_store_not_found", comment: "Shared store not found")
                        AppSyncState.current?.pendingShareError = msg
                        NotificationCenter.default.post(name: .shareAcceptanceFailed, object: msg)
                    }
                    return
                }

                PersistenceController.shared.container.acceptShareInvitations(
                    from: [metadata],
                    into: sharedStore
                ) { _, error in
                    DispatchQueue.main.async {
                        if let error = error {
                            let msg = self.sharingErrorMessage(for: error)
                            AppSyncState.current?.pendingShareError = msg
                            NotificationCenter.default.post(name: .shareAcceptanceFailed, object: msg)
                        } else {
                            self.appDelegate.waitForImportThenNotify(
                                persistenceController: PersistenceController.shared
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Error message helper

    private func sharingErrorMessage(for error: Error) -> String {
        if let ckError = error as? CKError {
            switch ckError.code {
            case .notAuthenticated:
                return "Devi effettuare l'accesso con il tuo Apple ID.\n\nVai in Impostazioni > [Il tuo nome] > iCloud."
            case .accountTemporarilyUnavailable:
                return "L'account iCloud non è ancora pronto. Attendi qualche secondo e riprova."
            case .networkFailure, .networkUnavailable:
                return "Connessione internet non disponibile. Verifica la connessione e riprova."
            case .quotaExceeded:
                return "Spazio iCloud insufficiente. Libera spazio e riprova."
            case .participantMayNeedVerification:
                return "Potrebbe essere necessario verificare il tuo account. Controlla le impostazioni iCloud."
            case .unknownItem:
                return "Il foglio condiviso non è più disponibile o è stato eliminato."
            case .badContainer:
                return "Errore di configurazione dell'app. Contatta il supporto."
            case .serviceUnavailable:
                return "Il servizio iCloud non è disponibile al momento. Riprova più tardi."
            case .zoneBusy:
                return "Il servizio è temporaneamente occupato. Riprova tra qualche minuto."
            case .requestRateLimited:
                return "Troppe richieste. Attendi qualche minuto prima di riprovare."
            case .alreadyShared:
                return "Questo foglio è già condiviso con te."
            case .referenceViolation:
                return "Errore nei riferimenti dei dati. Il foglio potrebbe essere corrotto."
            case .managedAccountRestricted:
                return "Il tuo account ha delle restrizioni che impediscono l'accesso ai fogli condivisi."
            default:
                return "Errore CloudKit \(ckError.code.rawValue):\n\(ckError.localizedDescription)"
            }
        }
        return "Errore sconosciuto:\n\(error.localizedDescription)"
    }
}
