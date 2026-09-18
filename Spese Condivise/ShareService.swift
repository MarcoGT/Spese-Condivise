import CoreData
import CloudKit

/// Creazione e recupero delle CKShare dei fogli.
///
/// Strategia: la share viene creata SUBITO alla creazione del foglio, in
/// background. Chiamare container.share() su un oggetto appena salvato e non
/// ancora esportato permette a CloudKit di collocarlo direttamente nella zona
/// condivisibile; chiamarlo più tardi (al tap su "condividi") obbliga il
/// mirroring a SPOSTARE l'oggetto dalla zona privata a una zona share, ed è
/// quello spostamento che in-sessione resta appeso senza mai richiamare la
/// callback (bug noto di NSPersistentCloudKitContainer, riprodotto anche su
/// account iCloud pulito). Al tap la share esiste già → link istantaneo.
enum ShareService {

    static let containerID = "iCloud.com.marcolagana.SharedExpenses"

    /// Garantisce che il foglio abbia una CKShare con URL, creandola se serve.
    /// Idempotente e sicura da richiamare più volte. `completion` (opzionale)
    /// è invocata sul main thread.
    static func ensureShare(
        for sheetID: NSManagedObjectID,
        completion: ((Result<URL, Error>) -> Void)? = nil
    ) {
        let container = PersistenceController.shared.container
        let ckContainer = CKContainer(identifier: containerID)

        DispatchQueue.global(qos: .userInitiated).async {
            if let existing = (try? container.fetchShares(matching: [sheetID]))?[sheetID] {
                if let url = existing.url {
                    // Share già esistente con URL → fatto.
                    DispatchQueue.main.async { completion?(.success(url)) }
                } else {
                    // Share pre-creata ma mai arrivata sul server (mirroring
                    // lento o inceppato): NON richiamare container.share(),
                    // salvala direttamente su CloudKit per ottenere la URL.
                    DispatchQueue.main.async {
                        uploadShare(existing, to: ckContainer) { result in
                            completion?(result)
                        }
                    }
                }
                return
            }

            // container.share() esegue lavoro SINCRONO sul thread chiamante
            // prima di completare in async: mai chiamarlo dal main (bloccherebbe
            // la UI, es. al salvataggio del foglio). Si usa un background
            // context dedicato e l'oggetto viene riletto lì.
            let bg = container.newBackgroundContext()
            bg.perform {
                guard let sheet = try? bg.existingObject(with: sheetID) as? SharedSheet else {
                    DispatchQueue.main.async { completion?(.failure(ShareError.sheetNotFound)) }
                    return
                }
                let title = (sheet.value(forKey: "name") as? String) ?? "Foglio Condiviso"

                container.share([sheet], to: nil) { _, share, _, error in
                    DispatchQueue.main.async {
                        if let error = error {
                            completion?(.failure(error))
                            return
                        }
                        guard let share = share else {
                            completion?(.failure(ShareError.noShareReturned))
                            return
                        }
                        share[CKShare.SystemFieldKey.title] = title as CKRecordValue
                        share.publicPermission = .readWrite

                        if let url = share.url {
                            completion?(.success(url))
                            // Propaga comunque titolo/permessi in background.
                            uploadShare(share, to: ckContainer, completion: nil)
                        } else {
                            uploadShare(share, to: ckContainer) { result in
                                completion?(result)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Salva la share direttamente su CloudKit (senza passare dal mirroring)
    /// per ottenerne la URL. Se la zona della share non esiste ancora sul
    /// server (mirroring che non ha mai completato l'export), la crea e
    /// riprova: il link non dipende così dallo stato del mirroring.
    private static func uploadShare(
        _ share: CKShare,
        to ckContainer: CKContainer,
        retryOnZoneMissing: Bool = true,
        completion: ((Result<URL, Error>) -> Void)?
    ) {
        let op = CKModifyRecordsOperation(recordsToSave: [share], recordIDsToDelete: nil)
        op.savePolicy = .changedKeys
        op.configuration.timeoutIntervalForRequest = 25
        op.configuration.timeoutIntervalForResource = 25
        op.modifyRecordsResultBlock = { result in
            DispatchQueue.main.async {
                switch result {
                    case .success:
                        if let url = share.url {
                            completion?(.success(url))
                        } else {
                            completion?(.failure(ShareError.noURL))
                        }
                    case .failure(let error):
                        if retryOnZoneMissing, isZoneNotFound(error) {
                            createZoneThenRetry(share, to: ckContainer, completion: completion)
                        } else {
                            completion?(.failure(error))
                        }
                }
            }
        }
        ckContainer.privateCloudDatabase.add(op)
    }

    private static func isZoneNotFound(_ error: Error) -> Bool {
        guard let ck = error as? CKError else { return false }
        if ck.code == .zoneNotFound { return true }
        if ck.code == .partialFailure,
           let partial = ck.partialErrorsByItemID?.values.compactMap({ $0 as? CKError }) {
            return partial.contains { $0.code == .zoneNotFound }
        }
        return false
    }

    private static func createZoneThenRetry(
        _ share: CKShare,
        to ckContainer: CKContainer,
        completion: ((Result<URL, Error>) -> Void)?
    ) {
        let zone = CKRecordZone(zoneID: share.recordID.zoneID)
        let zoneOp = CKModifyRecordZonesOperation(recordZonesToSave: [zone], recordZoneIDsToDelete: nil)
        zoneOp.configuration.timeoutIntervalForRequest = 25
        zoneOp.modifyRecordZonesResultBlock = { result in
            DispatchQueue.main.async {
                switch result {
                    case .success:
                        uploadShare(share, to: ckContainer, retryOnZoneMissing: false, completion: completion)
                    case .failure(let error):
                        completion?(.failure(error))
                }
            }
        }
        ckContainer.privateCloudDatabase.add(zoneOp)
    }

    /// Cancella la CKShare esistente (rotta/senza URL) e ne crea una nuova.
    /// Utile quando la share pre-creata non è mai arrivata su CloudKit Production.
    static func forceRecreateShare(
        for sheetID: NSManagedObjectID,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let container = PersistenceController.shared.container
        let ckContainer = CKContainer(identifier: containerID)

        DispatchQueue.global(qos: .userInitiated).async {
            // Cancella la share esistente se presente
            if let existing = (try? container.fetchShares(matching: [sheetID]))?[sheetID] {
                let deleteOp = CKModifyRecordsOperation(
                    recordsToSave: nil,
                    recordIDsToDelete: [existing.recordID]
                )
                deleteOp.configuration.timeoutIntervalForRequest = 25
                deleteOp.modifyRecordsResultBlock = { _ in
                    // Ricrea indipendentemente dall'esito della cancellazione
                    DispatchQueue.main.async {
                        createFreshShare(for: sheetID, container: container, ckContainer: ckContainer, completion: completion)
                    }
                }
                ckContainer.privateCloudDatabase.add(deleteOp)
            } else {
                DispatchQueue.main.async {
                    createFreshShare(for: sheetID, container: container, ckContainer: ckContainer, completion: completion)
                }
            }
        }
    }

    private static func createFreshShare(
        for sheetID: NSManagedObjectID,
        container: NSPersistentCloudKitContainer,
        ckContainer: CKContainer,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let bg = container.newBackgroundContext()
        bg.perform {
            guard let sheet = try? bg.existingObject(with: sheetID) as? SharedSheet else {
                DispatchQueue.main.async { completion(.failure(ShareError.sheetNotFound)) }
                return
            }
            let title = (sheet.value(forKey: "name") as? String) ?? "Foglio Condiviso"
            container.share([sheet], to: nil) { _, share, _, error in
                DispatchQueue.main.async {
                    if let error = error { completion(.failure(error)); return }
                    guard let share = share else { completion(.failure(ShareError.noShareReturned)); return }
                    share[CKShare.SystemFieldKey.title] = title as CKRecordValue
                    share.publicPermission = .readWrite
                    uploadShare(share, to: ckContainer) { result in
                        completion(result)
                    }
                }
            }
        }
    }

    // MARK: - Accettazione inviti

    /// Metadati già accettati in questa sessione: iOS può consegnare lo stesso
    /// invito sia via `windowScene(_:userDidAcceptCloudKitShareWith:)` sia via
    /// universal link, e una doppia `acceptShareInvitations` sullo stesso record
    /// fa fallire la seconda lasciando la UI in errore su una share in realtà ok.
    private static var acceptedShareIDs = Set<String>()
    private static let acceptLock = NSLock()

    private static func markAccepting(_ metadata: CKShare.Metadata) -> Bool {
        let key = metadata.share.recordID.recordName
        acceptLock.lock()
        defer { acceptLock.unlock() }
        return acceptedShareIDs.insert(key).inserted
    }

    private static func unmarkAccepting(_ metadata: CKShare.Metadata) {
        let key = metadata.share.recordID.recordName
        acceptLock.lock()
        acceptedShareIDs.remove(key)
        acceptLock.unlock()
    }

    /// Unico punto di accettazione di un invito: usato dal SceneDelegate,
    /// dall'AppDelegate e dal percorso universal link. Attende che gli store
    /// siano pronti, deduplica gli inviti ripetuti, riprova sugli errori
    /// transitori e riporta l'esito su `AppSyncState`.
    static func acceptInvitation(_ metadata: CKShare.Metadata, attempt: Int = 0) {
        let persistence = PersistenceController.shared

        guard attempt > 0 || markAccepting(metadata) else { return }

        persistence.executeWhenReady {
            guard let sharedStore = persistence.sharedPersistentStore else {
                unmarkAccepting(metadata)
                reportAcceptFailure(NSLocalizedString("share_store_not_found", comment: ""))
                return
            }

            persistence.container.acceptShareInvitations(
                from: [metadata],
                into: sharedStore
            ) { _, error in
                DispatchQueue.main.async {
                    guard let error = error else {
                        AppDelegate.shared?.waitForImportThenNotify(
                            persistenceController: persistence
                        )
                        return
                    }

                    // Già accettata in precedenza: non è un errore per l'utente,
                    // il foglio è (o sarà) nella lista.
                    if let ck = error as? CKError, ck.code == .alreadyShared {
                        AppDelegate.shared?.waitForImportThenNotify(
                            persistenceController: persistence
                        )
                        return
                    }

                    if isRetryable(error), attempt < 3 {
                        let delay = retryDelay(for: error, attempt: attempt)
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            acceptInvitation(metadata, attempt: attempt + 1)
                        }
                        return
                    }

                    unmarkAccepting(metadata)
                    reportAcceptFailure(acceptErrorMessage(for: error))
                }
            }
        }
    }

    private static func isRetryable(_ error: Error) -> Bool {
        guard let ck = error as? CKError else { return false }
        switch ck.code {
            case .networkFailure, .networkUnavailable, .serviceUnavailable,
                 .zoneBusy, .requestRateLimited, .accountTemporarilyUnavailable:
                return true
            default:
                return false
        }
    }

    private static func retryDelay(for error: Error, attempt: Int) -> Double {
        if let ck = error as? CKError,
           let suggested = ck.retryAfterSeconds, suggested > 0 {
            return min(suggested, 30)
        }
        return Double(1 << attempt) * 2
    }

    /// Pubblica l'errore PRIMA di spegnere il flag di attesa: la lista reagisce
    /// al primo dei due e deve mostrare l'errore, non il messaggio generico di
    /// "sincronizzazione lenta".
    static func reportAcceptFailure(_ message: String) {
        AppSyncState.current.pendingShareError = message
        AppSyncState.current.isSyncingSharedSheet = false
        NotificationCenter.default.post(name: .shareAcceptanceFailed, object: message)
    }

    static func acceptErrorMessage(for error: Error) -> String {
        guard let ck = error as? CKError else {
            return String(
                format: NSLocalizedString("share_error_generic", comment: ""),
                error.localizedDescription
            )
        }
        switch ck.code {
            case .notAuthenticated:
                return NSLocalizedString("share_error_not_authenticated", comment: "")
            case .accountTemporarilyUnavailable:
                return NSLocalizedString("share_error_account_unavailable", comment: "")
            case .networkFailure, .networkUnavailable:
                return NSLocalizedString("share_error_network", comment: "")
            case .quotaExceeded:
                return NSLocalizedString("share_error_quota", comment: "")
            case .participantMayNeedVerification:
                return NSLocalizedString("share_error_verification", comment: "")
            case .unknownItem:
                return NSLocalizedString("share_error_unknown_item", comment: "")
            case .badContainer:
                return NSLocalizedString("share_error_bad_container", comment: "")
            case .serviceUnavailable:
                return NSLocalizedString("share_error_service_unavailable", comment: "")
            case .zoneBusy:
                return NSLocalizedString("share_error_zone_busy", comment: "")
            case .requestRateLimited:
                return NSLocalizedString("share_error_rate_limited", comment: "")
            case .managedAccountRestricted:
                return NSLocalizedString("share_error_managed_account", comment: "")
            default:
                return String(
                    format: NSLocalizedString("share_error_generic", comment: ""),
                    ck.localizedDescription
                )
        }
    }

    enum ShareError: LocalizedError {
        case sheetNotFound
        case noShareReturned
        case noURL

        var errorDescription: String? {
            switch self {
                case .sheetNotFound:
                    return NSLocalizedString("share_creation_failed", comment: "")
                case .noShareReturned:
                    return NSLocalizedString("share_creation_failed", comment: "")
                case .noURL:
                    return NSLocalizedString("Link non disponibile. Riprova tra qualche secondo.", comment: "")
            }
        }
    }
}
