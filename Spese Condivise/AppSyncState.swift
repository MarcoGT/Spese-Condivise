import Foundation
import Combine

final class AppSyncState: ObservableObject {
    @Published var initialSyncCompleted = false
    @Published var showOverlay = false
}
