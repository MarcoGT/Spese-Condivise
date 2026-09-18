import Foundation
import Combine

final class AppSyncState: ObservableObject {
    @Published var initialSyncCompleted = false
    @Published var showOverlay = false

    // Share acceptance result — set by AppDelegate or handleCloudKitShare,
    // consumed by SharedSheetListView via .onChange.
    @Published var pendingShareSuccess = false
    @Published var pendingShareError: String? = nil

    // True while the app is waiting for the newly-accepted sheet to appear
    // in the list (CloudKit sync can be slow). Cleared when the sheet arrives
    // or after a timeout.
    @Published var isSyncingSharedSheet = false

    // Istanza unica: AppDelegate/SceneDelegate non hanno l'environment SwiftUI
    // e devono poter riportare l'esito di una share anche a freddo, PRIMA che
    // la prima view sia comparsa. Con un riferimento weak popolato in .onAppear
    // un invito aperto ad app chiusa finiva nel vuoto senza alcun messaggio.
    static let current = AppSyncState()
}
