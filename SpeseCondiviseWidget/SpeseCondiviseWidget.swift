import WidgetKit
import SwiftUI

struct WidgetSheetData: Codable {
    let name: String
    let balance: Double
}

struct WidgetEntry: TimelineEntry {
    let date: Date
    let totalBalance: Double
    let sheets: [WidgetSheetData]
}

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

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: Date(), totalBalance: 0, sheets: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        let entry = WidgetStore.read()
        let next  = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct SpeseCondiviseWidgetEntryView: View {
    var entry: Provider.Entry
    var body: some View {
        Text("Spese Condivise")
    }
}

struct SpeseCondiviseWidget: Widget {
    let kind = "SpeseCondiviseWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            SpeseCondiviseWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Spese Condivise")
        .description("Il tuo saldo.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
