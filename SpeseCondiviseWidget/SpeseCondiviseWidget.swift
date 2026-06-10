import WidgetKit
import SwiftUI

// MARK: - Shared data model

struct WidgetSheetData: Codable {
    let name: String
    let balance: Double
}

struct WidgetEntry: TimelineEntry {
    let date: Date
    let totalBalance: Double
    let sheets: [WidgetSheetData]
}

// MARK: - Data reader

private enum WidgetStore {
    static let suiteName  = "group.com.marcolagana.SharedExpenses"
    static let balanceKey = "widget.totalBalance"
    static let sheetsKey  = "widget.sheets"

    static func read() -> WidgetEntry {
        let defaults = UserDefaults(suiteName: suiteName)
        let balance  = defaults?.double(forKey: balanceKey) ?? 0
        let sheets: [WidgetSheetData]
        if let data    = defaults?.data(forKey: sheetsKey),
           let decoded = try? JSONDecoder().decode([WidgetSheetData].self, from: data) {
            sheets = decoded
        } else {
            sheets = []
        }
        return WidgetEntry(date: Date(), totalBalance: balance, sheets: sheets)
    }
}

// MARK: - Provider

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: Date(), totalBalance: -45.50, sheets: [
            WidgetSheetData(name: "Viaggio Roma", balance: -34.00),
            WidgetSheetData(name: "Casa",          balance: -11.50)
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> ()) {
        completion(WidgetStore.read())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> ()) {
        let entry      = WidgetStore.read()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

// MARK: - Formatting helper

private func formatAmount(_ value: Double) -> String {
    let f = NumberFormatter()
    f.numberStyle          = .decimal
    f.minimumFractionDigits = 2
    f.maximumFractionDigits = 2
    f.locale               = Locale.current
    return (f.string(from: NSNumber(value: value)) ?? "0,00") + " €"
}

// MARK: - Small widget view

private struct SmallWidgetView: View {
    let entry: WidgetEntry

    private var isEven:     Bool  { abs(entry.totalBalance) < 0.01 }
    private var isPositive: Bool  { entry.totalBalance > 0 }
    private var accent:     Color { isEven ? .secondary : (isPositive ? .green : .red) }
    private var label: String {
        isEven ? "In pari" : (isPositive ? "In credito" : "In debito")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "eurosign.circle.fill")
                    .foregroundColor(accent)
                    .font(.system(size: 13, weight: .semibold))
                Text("Spese Condivise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text(formatAmount(abs(entry.totalBalance)))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(accent)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Medium widget view

private struct MediumWidgetView: View {
    let entry: WidgetEntry

    private var isEven:     Bool  { abs(entry.totalBalance) < 0.01 }
    private var isPositive: Bool  { entry.totalBalance > 0 }
    private var accent:     Color { isEven ? .secondary : (isPositive ? .green : .red) }
    private var label: String {
        isEven ? "In pari" : (isPositive ? "In credito" : "In debito")
    }

    var body: some View {
        HStack(spacing: 0) {
            // Colonna sinistra — saldo totale
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "eurosign.circle.fill")
                        .foregroundColor(accent)
                        .font(.system(size: 12, weight: .semibold))
                    Text("Saldo totale")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(formatAmount(abs(entry.totalBalance)))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(accent)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            // Divisore
            Rectangle()
                .fill(accent.opacity(0.15))
                .frame(width: 1)
                .padding(.vertical, 14)

            // Colonna destra — lista fogli
            VStack(alignment: .leading, spacing: 8) {
                if entry.sheets.isEmpty {
                    Spacer()
                    Text("Nessun foglio")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                } else {
                    ForEach(entry.sheets.prefix(3), id: \.name) { sheet in
                        HStack(spacing: 4) {
                            let even = abs(sheet.balance) < 0.01
                            let pos  = sheet.balance > 0
                            let c: Color = even ? .secondary : (pos ? .green : .red)
                            Text(sheet.name)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            Spacer()
                            Text((pos ? "+" : "−") + formatAmount(abs(sheet.balance)))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(c)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: - Entry view

struct SpeseCondiviseWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family

    private var isEven:     Bool    { abs(entry.totalBalance) < 0.01 }
    private var isPositive: Bool    { entry.totalBalance > 0 }
    private var gradient: [Color] {
        isEven    ? [Color(.systemGray5), Color(.systemGray6)]
        : isPositive ? [Color.green.opacity(0.30), Color.green.opacity(0.05)]
                     : [Color.red.opacity(0.30),   Color.red.opacity(0.05)]
    }

    var body: some View {
        Group {
            switch family {
            case .systemMedium: MediumWidgetView(entry: entry)
            default:            SmallWidgetView(entry: entry)
            }
        }
        .containerBackground(
            LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing),
            for: .widget
        )
    }
}

// MARK: - Widget

struct SpeseCondiviseWidget: Widget {
    let kind = "SpeseCondiviseWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            SpeseCondiviseWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Spese Condivise")
        .description("Il tuo saldo totale, sempre in vista.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Preview

#Preview(as: .systemSmall) {
    SpeseCondiviseWidget()
} timeline: {
    WidgetEntry(date: .now, totalBalance: -45.50, sheets: [
        WidgetSheetData(name: "Viaggio Roma", balance: -34.00),
        WidgetSheetData(name: "Casa",          balance: -11.50)
    ])
}

#Preview(as: .systemMedium) {
    SpeseCondiviseWidget()
} timeline: {
    WidgetEntry(date: .now, totalBalance: -45.50, sheets: [
        WidgetSheetData(name: "Viaggio Roma", balance: -34.00),
        WidgetSheetData(name: "Casa",          balance: -11.50)
    ])
}
