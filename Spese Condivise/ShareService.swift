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
            // Share già esistente con URL → fatto.
            if let existing = (try? container.fetchShares(matching: [sheetID]))?[sheetID],
               let url = existing.url {
                DispatchQueue.main.async { completion?(.success(url)) }
                return
            }

            DispatchQueue.main.async {
                guard let sheet = try? container.viewContext.existingObject(with: sheetID) as? SharedSheet else {
                    completion?(.failure(ShareError.sheetNotFound))
                    return
                }
                let title = sheet.name ?? "Foglio Condiviso"

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
    /// per ottenerne la URL.
    private static func uploadShare(
        _ share: CKShare,
        to ckContainer: CKContainer,
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
                        completion?(.failure(error))
                }
            }
        }
        ckContainer.privateCloudDatabase.add(op)
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
