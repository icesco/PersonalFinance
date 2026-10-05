import SwiftUI
import WidgetKit

private struct ExpenseEntry: TimelineEntry {
    let date: Date
}

private struct ExpenseProvider: TimelineProvider {
    func placeholder(in context: Context) -> ExpenseEntry { ExpenseEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (ExpenseEntry) -> Void) {
        completion(ExpenseEntry(date: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ExpenseEntry>) -> Void) {
        completion(Timeline(entries: [ExpenseEntry(date: .now)], policy: .never))
    }
}

private struct ExpenseComplicationView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Label("Prepara spesa", systemImage: "plus.circle.fill")
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Label("Forgia", systemImage: "flame.fill")
                        .font(.caption).foregroundStyle(.secondary)
                    Label("Prepara spesa", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)
                }
            case .accessoryCorner:
                Image(systemName: "plus.circle.fill")
                    .font(.title)
                    .widgetLabel { Text("Spesa") }
            default:
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "plus")
                        .font(.title2.bold())
                }
            }
        }
        .accessibilityLabel("Prepara una spesa in Forgia")
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(URL(string: "forgia://watch/expense"))
    }
}

@main
struct ForgiaWatchWidgets: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ForgiaWatchExpense", provider: ExpenseProvider()) { _ in
            ExpenseComplicationView()
        }
        .configurationDisplayName("Prepara spesa")
        .description("Apri una bozza sul Watch da confermare su iPhone.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular])
    }
}
