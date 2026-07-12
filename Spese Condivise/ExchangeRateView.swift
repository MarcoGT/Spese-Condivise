import SwiftUI
import CoreData

struct ExchangeRateView: View {

    @ObservedObject var sheet: SharedSheet
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var rateText: String = ""
    @State private var currencyCode: String = "EUR"

    private let commonCurrencies = ["EUR", "USD", "GBP", "CHF", "JPY", "CAD", "AUD", "SEK", "NOK", "DKK"]

    private var sheetCurrency: String { sheet.currencyCode ?? "EUR" }

    private var availableCurrencies: [String] {
        commonCurrencies.filter { $0 != sheetCurrency }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(String(format: NSLocalizedString("exchange_rate_explain", comment: ""), sheetCurrency))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                Section(header: Text(NSLocalizedString("exchange_rate_home_currency", comment: ""))) {
                    Picker(NSLocalizedString("exchange_rate_home_currency", comment: ""), selection: $currencyCode) {
                        ForEach(availableCurrencies, id: \.self) { code in
                            Text("\(code)  \(currencyName(code))").tag(code)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.wheel)
                    .frame(height: 120)
                }

                Section(header: Text(String(format: NSLocalizedString("exchange_rate_field_header", comment: ""), sheetCurrency, currencyCode))) {
                    HStack {
                        Text("1 \(sheetCurrency) =")
                            .foregroundColor(.secondary)
                        TextField("0.92", text: $rateText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text(currencyCode)
                            .foregroundColor(.secondary)
                    }
                }

                if sheet.reimbursementCurrencyCode != nil && sheet.exchangeRate > 0 {
                    Section {
                        Button(role: .destructive) {
                            sheet.reimbursementCurrencyCode = nil
                            sheet.exchangeRate = 0
                            try? viewContext.save()
                            dismiss()
                        } label: {
                            Label(NSLocalizedString("exchange_rate_remove", comment: ""), systemImage: "xmark.circle")
                        }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("exchange_rate_title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("cancel", comment: "")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("save", comment: "")) { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear { loadExisting() }
        }
    }

    private var canSave: Bool {
        guard let v = Double(rateText.replacingOccurrences(of: ",", with: ".")) else { return false }
        return v > 0
    }

    private func loadExisting() {
        if let existing = sheet.reimbursementCurrencyCode, !existing.isEmpty, existing != sheetCurrency {
            currencyCode = existing
        } else {
            currencyCode = availableCurrencies.first ?? "EUR"
        }
        if sheet.exchangeRate > 0 {
            rateText = String(format: "%.4f", sheet.exchangeRate)
                .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
        }
    }

    private func save() {
        guard let rate = Double(rateText.replacingOccurrences(of: ",", with: ".")) else { return }
        sheet.reimbursementCurrencyCode = currencyCode
        sheet.exchangeRate = rate
        try? viewContext.save()
        dismiss()
    }

    private func currencyName(_ code: String) -> String {
        Locale.current.localizedString(forCurrencyCode: code) ?? code
    }
}
