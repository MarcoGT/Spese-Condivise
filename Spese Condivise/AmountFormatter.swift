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

    /// Restituisce una stringa come "14,30 €" o "14.30 €" a seconda del locale.
    static func format(_ value: Double, currencySymbol: String = "€") -> String {
        let formatted = formatter.string(from: NSNumber(value: value))
            ?? String(format: "%.2f", value)
        return "\(formatted) \(currencySymbol)"
    }
}

extension Double {
    /// Convenience: `expense.amount.amountString`
    var amountString: String { AmountFormatter.format(self) }
}
