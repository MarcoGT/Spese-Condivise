import Foundation
import Combine

final class AppSyncState: ObservableObject {
    @Published var initialSyncCompleted = false
    @Published var showOverlay = false

    // Share acceptance result — set by AppDelegate or handleCloudKitShare,
    // consumed by SharedSheetListView via .onChange.
    @Published var pendingShareSuccess = false
    @Published var pendingShareError: String? = nil

    // Static accessor so AppDelegate (which has no SwiftUI environment) can
    // reach the live instance created in SharedExpensesApp.
    static weak var current: AppSyncState?
}
