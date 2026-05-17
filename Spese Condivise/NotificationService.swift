import Foundation
import CloudKit
import UserNotifications
import CoreData
import UIKit
import SwiftUI

/// Gestisce permessi, subscriptions CloudKit e notifiche locali.
final class NotificationService {

    static let shared = NotificationService()
    private init() {}

    // MARK: - Permessi

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    // MARK: - CKDatabaseSubscription

    /// Registra le subscription su private e shared database.
    /// Sicuro chiamarlo più volte — CloudKit aggiorna quella esistente.
    func setupSubscriptions() {
        setupSubscription(
            id: "private-db-changes",
            database: CKContainer(identifier: "iCloud.com.marcolagana.SharedExpenses").privateCloudDatabase
        )
        setupSubscription(
            id: "shared-db-changes",
            database: CKContainer(identifier: "iCloud.com.marcolagana.SharedExpenses").sharedCloudDatabase
        )
    }

    private func setupSubscription(id: String, database: CKDatabase) {
        let subscription = CKDatabaseSubscription(subscriptionID: id)
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true  // silent push
        subscription.notificationInfo = notificationInfo

        let op = CKModifySubscriptionsOperation(
            subscriptionsToSave: [subscription],
            subscriptionIDsToDelete: nil
        )
        op.modifySubscriptionsResultBlock = { _ in }
        database.add(op)
    }

    // MARK: - Notifica locale dopo import CloudKit

    /// Da chiamare dopo che NSPersistentCloudKitContainer ha completato un import.
    /// Controlla se ci sono spese nuove (createdAt > lastSeenAt) e mostra una notifica.
    func notifyIfNeeded(context: NSManagedObjectContext) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }

            context.perform {
                let fetch = NSFetchRequest<Expense>(entityName: "Expense")
                fetch.predicate = NSPredicate(
                    format: "createdAt > %@ AND archived == NO",
                    LastSeenStore.globalLastSeen as CVarArg
                )
                fetch.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
                fetch.fetchLimit = 1

                guard
                    let newest = try? context.fetch(fetch).first,
                    let sheet = newest.sheet,
                    let sheetName = sheet.name
                else { return }

                // Non notificare se l'app è in foreground
                var isActive = false
                DispatchQueue.main.sync {
                    isActive = UIApplication.shared.applicationState == .active
                }
                guard !isActive else { return }

                self.postLocalNotification(sheetName: sheetName, expense: newest)
            }
        }
    }

    private func postLocalNotification(sheetName: String, expense: Expense) {
        let content = UNMutableNotificationContent()
        content.title = sheetName
        content.sound = .default

        if let note = expense.note, !note.isEmpty {
            content.body = String(
                format: NSLocalizedString("notification_new_expense_named", comment: ""),
                note,
                expense.amount.amountString
            )
        } else {
            content.body = String(
                format: NSLocalizedString("notification_new_expense", comment: ""),
                expense.amount.amountString
            )
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil  // immediata
        )
        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - LastSeenStore

/// Traccia quando l'utente ha visto l'ultima volta le spese.
/// Usato sia per le notifiche che per l'highlight in UI.
enum LastSeenStore {

    /// Data globale dell'ultimo import visto (per le notifiche push)
    static var globalLastSeen: Date {
        get { UserDefaults.standard.object(forKey: "globalLastSeen") as? Date ?? .distantPast }
        set { UserDefaults.standard.set(newValue, forKey: "globalLastSeen") }
    }

    /// Data dell'ultima apertura di un foglio specifico (per l'highlight in UI)
    static func lastSeen(for sheet: SharedSheet) -> Date {
        let key = "lastSeen_\(sheet.objectID.uriRepresentation().absoluteString)"
        return UserDefaults.standard.object(forKey: key) as? Date ?? .distantPast
    }

    static func markSeen(for sheet: SharedSheet) {
        let key = "lastSeen_\(sheet.objectID.uriRepresentation().absoluteString)"
        UserDefaults.standard.set(Date(), forKey: key)
    }

    /// Quante spese nuove ci sono in un foglio (non ancora viste dall'utente)
    static func newExpensesCount(for sheet: SharedSheet) -> Int {
        let seen = lastSeen(for: sheet)
        return sheet.activeExpensesArray.filter {
            ($0.createdAt ?? .distantPast) > seen
        }.count
    }
}
