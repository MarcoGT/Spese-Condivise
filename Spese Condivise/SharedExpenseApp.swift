import SwiftUI
import CloudKit
import CoreData

@main
struct SharedExpensesApp: App {
    let persistenceController = PersistenceController.shared
    @State private var showingShareError = false
    @State private var shareErrorMessage = ""
    @State private var showingShareSuccess = false
    private let cloudContainer = CKContainer(identifier: "iCloud.com.marcolagana.SharedExpenses")
    @State private var isInitialSyncCompleted = false
    @StateObject private var syncState = AppSyncState()



    
    var body: some Scene {
        WindowGroup {
            SharedSheetListView()
                .environment(\.managedObjectContext,
                              persistenceController.container.viewContext)
                .environmentObject(persistenceController)   // ← OBBLIGATORIA
                .environmentObject(syncState)
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
                    if let url = userActivity.webpageURL {
                        handleIncomingURL(url)
                    }
                }
                .alert(NSLocalizedString("sharing error", comment: "sharing error"), isPresented: $showingShareError) {
                    Button("OK") { }
                } message: {
                    Text(shareErrorMessage)
                }
                .alert(NSLocalizedString("added shared sheet", comment: "added shared sheet"), isPresented: $showingShareSuccess) {
                    Button(NSLocalizedString("OK", comment: "OK")) { }
                } message: {
                    Text(NSLocalizedString("The shared sheet has been added to your list, you can see it in a few seconds", comment: "shared sheet added"))
                }
                .onAppear {
                    prewarmCloudKit()
                    observeCloudKitSync()
                }
        }
    }
    
    private func observeCloudKitSync() {
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: persistenceController.container.persistentStoreCoordinator,
            queue: .main
        ) { _ in
                // Prima notifica = import avvenuto
            isInitialSyncCompleted = true
        }
    }

    
    private func prewarmCloudKit() {
        let context = persistenceController.container.viewContext
        
        context.perform {
            let request = NSFetchRequest<NSFetchRequestResult>(
                entityName: "SharedSheet"
            )
            request.fetchLimit = 1
            _ = try? context.fetch(request)
        }
    }
    
        // MARK: - CloudKit Sharing Support
    
    private func handleIncomingURL(_ url: URL) {
        print("📱 Ricevuto URL: \(url)")
        
            // Verifica se è un link di condivisione CloudKit
        if url.absoluteString.contains("icloud.com") && url.absoluteString.contains("share") {
            print("📱 Rilevato link di condivisione CloudKit: \(url)")
            handleCloudKitShare(url: url)
        }
    }
    
    private func handleCloudKitShare(url: URL) {
        let container = cloudContainer
        
        print("🔄 Recupero metadati condivisione...")
        
            // Ottieni i metadati della condivisione
        container.fetchShareMetadata(with: url) { (metadata, error) in
            if let error = error {
                print("❌ Errore nel recupero metadati condivisione: \(error)")
                DispatchQueue.main.async {
                    self.showSharingError(error: error)
                }
                return
            }
            
            guard let metadata = metadata else {
                print("❌ Metadati condivisione nulli")
                DispatchQueue.main.async {
                    self.shareErrorMessage = "Link di condivisione non valido."
                    self.showingShareError = true
                }
                return
            }
            
            print("✅ Metadati ricevuti, accetto la condivisione...")
            print("📋 Titolo condivisione: \( metadata.share.url?.absoluteString ?? "N/A")")
            print("👤 Proprietario: \(metadata.ownerIdentity.nameComponents?.formatted() ?? "N/A")")
            
                // Accetta la condivisione
            container.accept(metadata) { (share, error) in
                DispatchQueue.main.async {
                    if let error = error {
                        print("❌ Errore nell'accettare la condivisione: \(error)")
                        self.showSharingError(error: error)
                    } else {
                        print("✅ Condivisione accettata con successo")
                        print("📁 Share URL: \(share?.url?.absoluteString ?? "N/A")")
                        self.showingShareSuccess = true
                        
                            // Forza il refresh dei dati Core Data dopo un breve delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            print("🔄 Forzando refresh dei dati...")
                            NotificationCenter.default.post(
                                name: .NSPersistentStoreRemoteChange,
                                object: self.persistenceController.container.persistentStoreCoordinator
                            )
                            
                                // Forza anche un refresh del viewContext
                            self.persistenceController.container.viewContext.refreshAllObjects()
                        }
                    }
                }
            }
        }
    }
    
    private func showSharingError(error: Error) {
        print("🔍 Analizzando errore: \(error)")
        
            // Gestisci errori specifici CloudKit
        if let ckError = error as? CKError {
            print("📊 Codice errore CloudKit: \(ckError.code.rawValue)")
            print("📝 Descrizione errore: \(ckError.localizedDescription)")
            
            switch ckError.code {
                case .notAuthenticated:
                    shareErrorMessage = "Devi effettuare l'accesso con il tuo Apple ID per accedere ai fogli condivisi.\n\nVai in Impostazioni > [Il tuo nome] > iCloud e assicurati di essere connesso."
                case .networkFailure, .networkUnavailable:
                    shareErrorMessage = "Connessione internet non disponibile. Verifica la tua connessione e riprova."
                case .quotaExceeded:
                    shareErrorMessage = "Spazio iCloud insufficiente per accedere al foglio condiviso. Libera spazio nelle impostazioni iCloud."
                case .participantMayNeedVerification:
                    shareErrorMessage = "Potrebbe essere necessario verificare il tuo account. Controlla le impostazioni iCloud."
                case .unknownItem:
                    shareErrorMessage = "Il foglio condiviso non è più disponibile o è stato eliminato."
                case .badContainer:
                    shareErrorMessage = "Errore di configurazione dell'app. Contatta il supporto."
                case .serviceUnavailable:
                    shareErrorMessage = "Il servizio iCloud non è disponibile al momento. Riprova più tardi."
                case .zoneBusy:
                    shareErrorMessage = "Il servizio è temporaneamente occupato. Riprova tra qualche minuto."
                case .requestRateLimited:
                    shareErrorMessage = "Troppe richieste. Aspetta qualche minuto prima di riprovare."
                case .alreadyShared:
                    shareErrorMessage = "Questo foglio è già condiviso con te."
                case .referenceViolation:
                    shareErrorMessage = "Errore nei riferimenti dei dati. Il foglio potrebbe essere corrotto."
                case .managedAccountRestricted:
                    shareErrorMessage = "Il tuo account ha delle restrizioni che impediscono l'accesso ai fogli condivisi."
                default:
                    shareErrorMessage = "Errore nell'accedere al foglio condiviso:\n\(ckError.localizedDescription)\n\nCodice errore: \(ckError.code.rawValue)"
            }
        } else {
            shareErrorMessage = "Errore sconosciuto nell'accedere al foglio condiviso:\n\(error.localizedDescription)"
        }
        
        showingShareError = true
    }
}
