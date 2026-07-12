import Foundation

enum CurrencyList {

    /// Valute ordinate per area geografica / frequenza d'uso in viaggi.
    static let all: [String] = [
        // Europa
        "EUR", "GBP", "CHF", "NOK", "SEK", "DKK", "PLN", "CZK", "HUF", "RON",
        // Americhe
        "USD", "CAD", "MXN", "BRL", "ARS", "CLP", "COP",
        // Asia-Pacifico
        "JPY", "CNY", "KRW", "HKD", "SGD", "AUD", "NZD", "INR", "THB", "IDR", "MYR", "PHP", "VND", "TWD",
        // Medio Oriente / Africa
        "AED", "SAR", "TRY", "EGP", "MAD", "ZAR", "ILS",
    ]

    static func label(for code: String) -> String {
        let name = Locale.current.localizedString(forCurrencyCode: code) ?? code
        let symbol = AmountFormatter.symbol(for: code)
        if symbol != code {
            return "\(code) · \(name) (\(symbol))"
        }
        return "\(code) · \(name)"
    }
}
