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
    @Parameter(title: "Conti", description: "Se non scegli un conto, vengono inclusi tutti i conti del libro.")
    var accounts: [WidgetBalanceAccountEntity]?
    @Parameter(title: "Mostra legenda", default: true) var showLegend: Bool
    static var parameterSummary: some ParameterSummary {
        Summary("Saldo di \(\.$book) · \(\.$period)") {
            \.$accounts
            \.$showLegend
        }
    }
}

struct WidgetBalanceAccountEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Conto"
    static let defaultQuery = WidgetBalanceAccountQuery()
    let id: UUID
    let name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct WidgetBalanceAccountQuery: EntityQuery {
    @IntentParameterDependency<FinanceBalanceConfiguration>(\.$book) var configuration

    func entities(for identifiers: [UUID]) async throws -> [WidgetBalanceAccountEntity] {
        let snapshot = FinanceWidgetStorage.read(from: FinanceWidgetStorage.sharedURL)
        let series = snapshot.usable(at: Date()) ? snapshot.books.flatMap { $0.balanceHistories?.first?.series ?? [] } : []
        let values = Dictionary(series.map { ($0.id, WidgetBalanceAccountEntity(id: $0.id, name: $0.name)) },
                                uniquingKeysWith: { first, _ in first })
        return identifiers.map { values[$0] ?? WidgetBalanceAccountEntity(id: $0, name: "Conto non disponibile") }
    }

    func suggestedEntities() async throws -> [WidgetBalanceAccountEntity] {
        let snapshot = FinanceWidgetStorage.read(from: FinanceWidgetStorage.sharedURL)
        guard snapshot.usable(at: Date()) else { return [] }
        let book: WidgetBookSnapshot?
        if let selected = configuration?.book {
            book = snapshot.books.first { $0.id == selected.id }
        } else {
            book = snapshot.books.first
        }
        return (book?.balanceHistories?.first?.series ?? []).map { WidgetBalanceAccountEntity(id: $0.id, name: $0.name) }
    }
}

struct FinanceBalanceEntry: TimelineEntry {
    let date: Date
    let snapshot: FinanceWidgetSnapshot
    let bookID: UUID?
    let period: WidgetBalancePeriod
    var accountIDs: Set<UUID> = []
    var showLegend = true

    var book: WidgetBookSnapshot? {
        guard snapshot.usable(at: date) else { return nil }
        if let bookID { return snapshot.books.first { $0.id == bookID } }
        return snapshot.books.first
    }
    var history: WidgetBalanceSnapshot? {
        guard let history = book?.balanceHistories?.first(where: { $0.period == period }),
              history.interval.start <= date, date < history.interval.end, !history.series.isEmpty else { return nil }
        let selected = history.selecting(accountIDs: accountIDs)
        return selected.series.isEmpty ? nil : selected
    }
}

struct FinanceBalanceProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> FinanceBalanceEntry {
        FinanceBalanceEntry(date: Date(), snapshot: .empty(.hidden), bookID: nil, period: .month)
    }
    func snapshot(for configuration: FinanceBalanceConfiguration, in context: Context) async -> FinanceBalanceEntry {
        if context.isPreview {
            let sample = FinanceWidgetSample.snapshot
            let count = configuration.accounts?.count ?? 0
            let sampleIDs = count == 0 ? Set<UUID>() : Set((sample.books.first?.balanceHistories?.first?.series ?? [])
                .prefix(count).map(\.id))
            return FinanceBalanceEntry(date: Date(), snapshot: sample, bookID: FinanceWidgetSample.bookID,
                                       period: configuration.period.snapshotPeriod, accountIDs: sampleIDs, showLegend: configuration.showLegend)
        }
        return entry(for: configuration)
    }
    func timeline(for configuration: FinanceBalanceConfiguration, in context: Context) async -> Timeline<FinanceBalanceEntry> {
        let entry = entry(for: configuration)
        let nextRefresh = entry.date.addingTimeInterval(1800)
        guard let history = entry.history else {
            return Timeline(entries: [entry], policy: .after(nextRefresh))
        }
        let expiryDate = min(entry.snapshot.validUntil, history.interval.end)
        let expiry = FinanceBalanceEntry(date: expiryDate, snapshot: .empty(.unavailable), bookID: entry.bookID,
                                        period: entry.period, accountIDs: entry.accountIDs, showLegend: entry.showLegend)
        return Timeline(entries: [entry, expiry], policy: .after(min(nextRefresh, expiryDate)))
    }
    private func entry(for configuration: FinanceBalanceConfiguration) -> FinanceBalanceEntry {
        FinanceBalanceEntry(date: Date(), snapshot: FinanceWidgetStorage.read(from: FinanceWidgetStorage.sharedURL),
                            bookID: configuration.book?.id, period: configuration.period.snapshotPeriod,
                            accountIDs: Set(configuration.accounts?.map(\.id) ?? []), showLegend: configuration.showLegend)
    }
}

struct FinanceBalanceWidgetView: View {
    let entry: FinanceBalanceEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.financeWidgetTheme) private var theme
    private var tint: Color { BalanceWidgetTint.color(theme, history: entry.history) }

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
                                            size: contentSize, showLegend: entry.showLegend)
                    .privacySensitive()
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Spacer(minLength: 0)
                        Image("FormiMark").resizable().widgetAccentedRenderingMode(.accented).scaledToFit()
                            .frame(width: 18, height: 18).financeWidgetForeground(tint)
                            .accessibilityHidden(true)
                    }
                    if entry.book != nil, !entry.accountIDs.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Spacer(minLength: 0)
                            Text("Conti non disponibili").font(.headline)
                            Text("Modifica il widget per scegliere i conti di questo libro.")
                                .font(.caption).foregroundStyle(theme.palette.mutedText)
                            Spacer(minLength: 0)
                        }
                    } else {
                        FinanceWidgetStateView(hidden: entry.snapshot.state == .hidden, tint: tint,
                                               compact: family == .systemSmall)
                    }
                }
            }
        }
        .containerBackground(for: .widget) {
            FinanceWidgetBackground(tint: entry.history?.series.count == 1 ? tint : nil)
        }
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
                               provider: FinanceBalanceProvider()) {
            FinanceBalanceWidgetView(entry: $0)
                .environment(\.financeWidgetTheme, FinanceWidgetAppearance.theme)
                .environment(\.locale, FinanceWidgetAppearance.locale)
        }
            .configurationDisplayName("Saldo per conto")
            .description("L’andamento dei tuoi conti e la previsione basata sui movimenti programmati.")
            .supportedFamilies(families)
    }
}
