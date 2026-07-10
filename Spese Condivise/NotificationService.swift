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
                // Rilevamento per ID (indipendente dagli orologi): una spesa è
                // "nuova" se il suo id non è mai stato visto su QUESTO device.
                // Il vecchio confronto createdAt > watermark falliva sui fogli
                // condivisi perché createdAt è l'orologio del mittente e il
                // watermark veniva avanzato da import intermedi vuoti.
                let fetch = NSFetchRequest<Expense>(entityName: "Expense")
                fetch.predicate = NSPredicate(format: "archived == NO")
                fetch.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

                let active = (try? context.fetch(fetch)) ?? []
                let currentIDs = Set(active.compactMap { $0.id?.uuidString })

                let known = LastSeenStore.knownExpenseIDs

                // Primo avvio / prima sync dopo l'installazione: registra tutto
                // come già visto, così non piovono notifiche per spese
                // preesistenti (es. appena si accetta un foglio condiviso).
                guard LastSeenStore.hasSeededKnownExpenses else {
                    LastSeenStore.knownExpenseIDs = currentIDs
                    LastSeenStore.hasSeededKnownExpenses = true
                    return
                }

                let newIDs = currentIDs.subtracting(known)

                // Aggiorna SEMPRE il set (anche se poi non notifichiamo): così
                // le spese aggiunte da noi stessi, o quelle viste in foreground,
                // non riemergono come "nuove" a un import successivo.
                LastSeenStore.knownExpenseIDs = currentIDs

                guard
                    let newest = active.first(where: { ($0.id?.uuidString).map { newIDs.contains($0) } ?? false }),
                    let sheet = newest.sheet,
                    let sheetName = sheet.name
                else { return }

                // Non notificare se l'app è in foreground.
                // viewContext è main-queue, quindi questo blocco gira già sul
                // main thread: leggere applicationState con DispatchQueue.main.sync
                // qui causerebbe un deadlock (crash EXC_BREAKPOINT in libdispatch).
                let isActive: Bool
                if Thread.isMainThread {
                    isActive = UIApplication.shared.applicationState == .active
                } else {
                    isActive = DispatchQueue.main.sync {
                        UIApplication.shared.applicationState == .active
                    }
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

    /// Data globale dell'ultimo import visto (per le notifiche push).
    /// Legacy: non più usato per il rilevamento (sostituito da knownExpenseIDs),
    /// mantenuto per compatibilità.
    static var globalLastSeen: Date {
        get { UserDefaults.standard.object(forKey: "globalLastSeen") as? Date ?? .distantPast }
        set { UserDefaults.standard.set(newValue, forKey: "globalLastSeen") }
    }

    /// ID (UUID string) delle spese già note su questo device: base del
    /// rilevamento delle notifiche, indipendente dagli orologi dei device.
    static var knownExpenseIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "knownExpenseIDs") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "knownExpenseIDs") }
    }

    /// true dopo il primo popolamento di knownExpenseIDs (evita notifiche
    /// per le spese preesistenti alla prima sincronizzazione).
    static var hasSeededKnownExpenses: Bool {
        get { UserDefaults.standard.bool(forKey: "hasSeededKnownExpenses") }
        set { UserDefaults.standard.set(newValue, forKey: "hasSeededKnownExpenses") }
    }

    /// Registra una spesa come già nota (usato alla creazione locale, così
    /// una spesa aggiunta da te non ti si ripresenta come "nuova").
    static func markExpenseKnown(_ id: UUID?) {
        guard let id = id else { return }
        var set = knownExpenseIDs
        set.insert(id.uuidString)
        knownExpenseIDs = set
    }

    /// Registra come già note TUTTE le spese attive correnti. Usato dopo
    /// l'accettazione di un foglio condiviso: le spese preesistenti del foglio
    /// non devono generare notifiche (solo quelle aggiunte in seguito).
    static func seedAllKnown(context: NSManagedObjectContext) {
        context.perform {
            let fetch = NSFetchRequest<Expense>(entityName: "Expense")
            fetch.predicate = NSPredicate(format: "archived == NO")
            let active = (try? context.fetch(fetch)) ?? []
            var set = knownExpenseIDs
            set.formUnion(active.compactMap { $0.id?.uuidString })
            knownExpenseIDs = set
            hasSeededKnownExpenses = true
        }
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
