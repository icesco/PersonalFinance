import AppIntents
import FinanceCore
import SwiftUI
import WidgetKit

// Persisted raw values remain stable if the configuration is extended later.
enum FinanceBalancePeriod: String, AppEnum {
    case week = "week", month = "month", quarter = "quarter", year = "year"
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Periodo"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .week: "Settimana", .month: "Mese", .quarter: "Trimestre", .year: "Anno"
    ]
    var snapshotPeriod: WidgetBalancePeriod { WidgetBalancePeriod(rawValue: rawValue)! }
}

struct FinanceBalanceConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Saldo per conto"
    @Parameter(title: "Libro") var book: WidgetBookEntity?
    @Parameter(title: "Periodo", default: .month) var period: FinanceBalancePeriod
    static var parameterSummary: some ParameterSummary {
        Summary("Saldo di \(\.$book) · \(\.$period)")
    }
}

struct FinanceBalanceEntry: TimelineEntry {
    let date: Date
    let snapshot: FinanceWidgetSnapshot
    let bookID: UUID?
    let period: WidgetBalancePeriod

    var book: WidgetBookSnapshot? {
        guard snapshot.usable(at: date) else { return nil }
        if let bookID { return snapshot.books.first { $0.id == bookID } }
        return snapshot.books.first
    }
    var history: WidgetBalanceSnapshot? {
        guard let history = book?.balanceHistories?.first(where: { $0.period == period }),
              history.interval.start <= date, date < history.interval.end, !history.series.isEmpty else { return nil }
        return history
    }
}

struct FinanceBalanceProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> FinanceBalanceEntry {
        FinanceBalanceEntry(date: Date(), snapshot: .empty(.hidden), bookID: nil, period: .month)
    }
    func snapshot(for configuration: FinanceBalanceConfiguration, in context: Context) async -> FinanceBalanceEntry {
        entry(for: configuration)
    }
    func timeline(for configuration: FinanceBalanceConfiguration, in context: Context) async -> Timeline<FinanceBalanceEntry> {
        let entry = entry(for: configuration)
        let nextRefresh = entry.date.addingTimeInterval(1800)
        guard let history = entry.history else {
            return Timeline(entries: [entry], policy: .after(nextRefresh))
        }
        let expiryDate = min(entry.snapshot.validUntil, history.interval.end)
        let expiry = FinanceBalanceEntry(date: expiryDate, snapshot: .empty(.unavailable), bookID: entry.bookID, period: entry.period)
        return Timeline(entries: [entry, expiry], policy: .after(min(nextRefresh, expiryDate)))
    }
    private func entry(for configuration: FinanceBalanceConfiguration) -> FinanceBalanceEntry {
        FinanceBalanceEntry(date: Date(), snapshot: FinanceWidgetStorage.read(from: FinanceWidgetStorage.sharedURL),
                            bookID: configuration.book?.id, period: configuration.period.snapshotPeriod)
    }
}

struct FinanceBalanceWidgetView: View {
    let entry: FinanceBalanceEntry
    @Environment(\.widgetFamily) private var family

    private var contentSize: FinanceBalanceWidgetSize {
        if #available(iOS 27.0, macOS 27.0, *), family == .systemExtraLargePortrait { return .extraLargePortrait }
        switch family {
        case .systemSmall: return .small
        case .systemMedium: return .medium
        case .systemExtraLarge: return .extraLarge
        default: return .large
        }
    }

    var body: some View {
        Group {
            if let book = entry.book, let history = entry.history {
                FinanceBalanceWidgetContent(history: history, bookName: book.name, currency: book.currency,
                                            size: contentSize)
                    .privacySensitive()
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Saldo per conto", systemImage: "chart.xyaxis.line").font(family == .systemSmall ? .caption : .headline)
                    Spacer(minLength: 0)
                    Label(entry.snapshot.state == .hidden ? "Dati nascosti" : "Apri Formi per aggiornare",
                          systemImage: entry.snapshot.state == .hidden ? "lock.fill" : "arrow.clockwise")
                        .font(family == .systemSmall ? .caption : .subheadline)
                    Text(entry.snapshot.state == .hidden
                         ? "Abilita i dati finanziari nei widget dalle impostazioni di Formi."
                         : "Scegli un libro disponibile e aggiorna i dati nell’app.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }
        }
        .containerBackground(.background, for: .widget)
        .widgetURL(FinanceWidgetRoute(destination: .analysis, bookID: entry.book?.id ?? entry.bookID).url)
    }
}

struct FinanceBalanceWidget: Widget {
    private var families: [WidgetFamily] {
        var families: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge]
        if #available(iOS 27.0, macOS 27.0, *) { families.append(.systemExtraLargePortrait) }
        return families
    }

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: FinanceWidgetStorage.balanceKind, intent: FinanceBalanceConfiguration.self,
                               provider: FinanceBalanceProvider()) { FinanceBalanceWidgetView(entry: $0) }
            .configurationDisplayName("Saldo per conto")
            .description("L’andamento dei tuoi conti e la previsione basata sui movimenti programmati.")
            .supportedFamilies(families)
    }
}
