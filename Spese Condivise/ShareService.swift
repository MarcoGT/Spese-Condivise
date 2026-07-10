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
