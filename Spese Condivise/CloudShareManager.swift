//
//  CloudShareManager.swift
//  Spese Condivise
//
//  Created by Marco on 15.12.25.
//


import CoreData
import CloudKit

enum CloudShareError: Error {
    case objectNotFound
    case shareCreationFailed
    case missingURL
}

final class CloudShareManager {
    
    static let shared = CloudShareManager()
    private init() {}
    
    func createOrFetchShare(
        for objectID: NSManagedObjectID,
        in context: NSManagedObjectContext,
        container: NSPersistentCloudKitContainer
    ) async throws -> CKShare {
        
        guard let object = try context.existingObject(with: objectID) as? NSManagedObject else {
            throw CloudShareError.objectNotFound
        }
        
        if object.objectID.isTemporaryID {
            try context.obtainPermanentIDs(for: [object])
            try context.save()
        }
        
            // 1. Prova a recuperare una share esistente
        let shares = try await container.fetchShares(matching: [object.objectID])
        if let existing = shares.first?.value {
            return existing
        }
        
            // 2. Altrimenti creala
        return try await withCheckedThrowingContinuation { continuation in
            container.share([object], to: nil) { _, share, _, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let share = share else {
                    continuation.resume(throwing: CloudShareError.shareCreationFailed)
                    return
                }
                continuation.resume(returning: share)
            }
        }
    }
}
