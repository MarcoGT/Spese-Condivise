import Foundation

/// Formatta importi monetari rispettando il separatore decimale del locale corrente
/// (virgola in Italia/EU, punto negli USA).
enum AmountFormatter {

    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.locale = Locale.current
        return f
    }()

    /// Restituisce una stringa come "14,30 €" o "14.30 $" a seconda del locale e della valuta.
    static func format(_ value: Double, currencySymbol: String = "€") -> String {
        let formatted = formatter.string(from: NSNumber(value: value))
            ?? String(format: "%.2f", value)
        return "\(formatted) \(currencySymbol)"
    }

    /// Formatta usando il codice ISO della valuta (es. "USD" → "$").
    static func format(_ value: Double, currencyCode: String) -> String {
        format(value, currencySymbol: symbol(for: currencyCode))
    }

    /// Converte un codice ISO valuta nel simbolo locale (es. "USD" → "$", "EUR" → "€").
    static func symbol(for code: String) -> String {
        let locale = NSLocale(localeIdentifier: NSLocale.localeIdentifier(
            fromComponents: [NSLocale.Key.currencyCode.rawValue: code]
        ))
        return locale.displayName(forKey: .currencySymbol, value: code) ?? code
    }
}

extension Double {
    /// Convenience: `expense.amount.amountString`
    var amountString: String { AmountFormatter.format(self) }
}
