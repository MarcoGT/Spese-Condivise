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
    @StateObject private var syncState = AppSyncState.current
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
        guard isCloudKitShareURL(url) else { return }
        AppSyncState.current.isSyncingSharedSheet = true
        fetchMetadataThenAccept(url: url, attempt: 0)
    }

    private func isCloudKitShareURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(), host.hasSuffix("icloud.com") else { return false }
        return url.path.hasPrefix("/share/")
    }

    /// `fetchShareMetadata` fallisce facilmente quando l'app è appena stata
    /// lanciata dal link (rete non ancora pronta, account iCloud in warm-up):
    /// senza retry l'utente vede solo un errore e il foglio non arriva mai.
    private func fetchMetadataThenAccept(url: URL, attempt: Int) {
        cloudContainer.fetchShareMetadata(with: url) { metadata, error in
            if let metadata = metadata, error == nil {
                ShareService.acceptInvitation(metadata)
                return
            }

            let isTransient: Bool = {
                guard let ck = error as? CKError else { return false }
                switch ck.code {
                    case .networkFailure, .networkUnavailable, .serviceUnavailable,
                         .zoneBusy, .requestRateLimited, .accountTemporarilyUnavailable:
                        return true
                    default:
                        return false
                }
            }()

            if isTransient, attempt < 3 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(1 << attempt) * 2) {
                    self.fetchMetadataThenAccept(url: url, attempt: attempt + 1)
                }
                return
            }

            DispatchQueue.main.async {
                ShareService.reportAcceptFailure(
                    error.map { ShareService.acceptErrorMessage(for: $0) }
                        ?? NSLocalizedString("share_unknown_error", comment: "")
                )
            }
        }
    }
}
