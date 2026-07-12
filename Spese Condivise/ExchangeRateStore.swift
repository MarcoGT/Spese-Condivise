import Foundation

enum ExchangeRateStore {

    private static func rateKey(for sheet: SharedSheet) -> String {
        "exchangeRate_\(sheet.id?.uuidString ?? sheet.objectID.uriRepresentation().absoluteString)"
    }

    private static func currencyKey(for sheet: SharedSheet) -> String {
        "reimbursementCurrency_\(sheet.id?.uuidString ?? sheet.objectID.uriRepresentation().absoluteString)"
    }

    static func exchangeRate(for sheet: SharedSheet) -> Double {
        UserDefaults.standard.double(forKey: rateKey(for: sheet))
    }

    static func reimbursementCurrency(for sheet: SharedSheet) -> String? {
        UserDefaults.standard.string(forKey: currencyKey(for: sheet))
    }

    static func set(rate: Double, currency: String, for sheet: SharedSheet) {
        UserDefaults.standard.set(rate, forKey: rateKey(for: sheet))
        UserDefaults.standard.set(currency, forKey: currencyKey(for: sheet))
    }

    static func remove(for sheet: SharedSheet) {
        UserDefaults.standard.removeObject(forKey: rateKey(for: sheet))
        UserDefaults.standard.removeObject(forKey: currencyKey(for: sheet))
    }
}
