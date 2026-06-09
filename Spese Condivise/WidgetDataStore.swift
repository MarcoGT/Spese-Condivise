import Foundation
import WidgetKit

/// Dati di un singolo foglio da passare al widget
struct WidgetSheetData: Codable {
    let name: String
    let balance: Double
}

/// Scrive i dati del saldo nel container condiviso App Group
/// così il widget può leggerli senza accedere a CoreData.
enum WidgetDataStore {
    static let suiteName = "group.com.marcolagana.SharedExpenses"
    private static let balanceKey  = "widget.totalBalance"
    private static let sheetsKey   = "widget.sheets"

    static func write(totalBalance: Double, sheets: [WidgetSheetData]) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        defaults.set(totalBalance, forKey: balanceKey)
        if let data = try? JSONEncoder().encode(sheets) {
            defaults.set(data, forKey: sheetsKey)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
