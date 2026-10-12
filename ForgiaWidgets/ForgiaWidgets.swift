import AppIntents
import FinanceCore
import SwiftUI
import WidgetKit

struct WidgetBookEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Libro"
    static let defaultQuery = WidgetBookQuery()
    let id: UUID
    let name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct WidgetBookQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [WidgetBookEntity] {
        let books = Dictionary(available().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // Keep a configured identity when hidden/deleted rather than choosing another book.
        return identifiers.map { books[$0] ?? WidgetBookEntity(id: $0, name: "Libro non disponibile") }
    }
    func suggestedEntities() async throws -> [WidgetBookEntity] { available() }
    private func available() -> [WidgetBookEntity] {
        let snapshot = FinanceWidgetStorage.read(from: FinanceWidgetStorage.sharedURL)
        guard snapshot.state == .ready else { return [] }
        return snapshot.books.map { WidgetBookEntity(id: $0.id, name: $0.name) }
    }
}

struct FinanceWidgetConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Riepilogo Formi"
    @Parameter(title: "Libro") var book: WidgetBookEntity?
    static var parameterSummary: some ParameterSummary { Summary("Riepilogo di \(\.$book)") }
}

struct FinanceWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: FinanceWidgetSnapshot
    let bookID: UUID?
    var book: WidgetBookSnapshot? {
        guard snapshot.usable(at: date) else { return nil }
        if let bookID { return snapshot.books.first { $0.id == bookID } }
        return snapshot.books.first
    }
}

struct FinanceWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> FinanceWidgetEntry {
        FinanceWidgetEntry(date: Date(), snapshot: .empty(.hidden), bookID: nil)
    }
    func snapshot(for configuration: FinanceWidgetConfiguration, in context: Context) async -> FinanceWidgetEntry {
        context.isPreview
            ? FinanceWidgetEntry(date: Date(), snapshot: FinanceWidgetSample.snapshot, bookID: FinanceWidgetSample.bookID)
            : entry(for: configuration)
    }
    func timeline(for configuration: FinanceWidgetConfiguration, in context: Context) async -> Timeline<FinanceWidgetEntry> {
        let entry = entry(for: configuration)
        let nextRefresh = entry.date.addingTimeInterval(1800)
        // Schedule a redacted entry at a period boundary even if the app isn't running.
        if entry.snapshot.usable(at: entry.date) {
            let expiry = FinanceWidgetEntry(date: entry.snapshot.validUntil, snapshot: .empty(.unavailable), bookID: entry.bookID)
            return Timeline(entries: [entry, expiry], policy: .after(min(nextRefresh, expiry.date)))
        }
        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }
    private func entry(for configuration: FinanceWidgetConfiguration) -> FinanceWidgetEntry {
        FinanceWidgetEntry(date: Date(), snapshot: FinanceWidgetStorage.read(from: FinanceWidgetStorage.sharedURL), bookID: configuration.book?.id)
    }
}

struct FinanceWidgetView: View {
    let entry: FinanceWidgetEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.financeWidgetTheme) private var theme
    private var accent: Color { theme.color }

    var body: some View {
        Group {
            #if os(iOS)
            switch family {
            case .accessoryCircular:
                VStack(spacing: 2) {
                    Image(systemName: "plus").font(.title2.bold())
                    Text("Spesa").font(.caption2)
                }
                .accessibilityLabel("Aggiungi una spesa in Formi")
            case .accessoryInline:
                Label("Nuova spesa", systemImage: "plus.circle")
            case .accessoryRectangular:
                FinanceLockScreenSummary(entry: entry)
            default:
                homeSummary
            }
            #else
            homeSummary
            #endif
        }
        .containerBackground(for: .widget) { FinanceWidgetBackground(tint: accent) }
        .widgetURL(FinanceWidgetRoute(destination: destination, bookID: entry.book?.id ?? entry.bookID).url)
    }

    private var destination: FinanceWidgetRoute.Destination {
        #if os(iOS)
        if family == .accessoryCircular || family == .accessoryInline { return .expense }
        #endif
        return entry.snapshot.state == .hidden ? .expense : .planning
    }

    private var homeSummary: some View {
        VStack(alignment: .leading, spacing: 0) {
            FinanceWidgetHeader(title: entry.book?.budget != nil ? "Budget" : "Questo mese",
                                icon: entry.book?.budget != nil ? "target" : "chart.bar.fill",
                                tint: accent, compact: family == .systemSmall) {
                if family != .systemSmall {
                    Link(destination: FinanceWidgetRoute(destination: .expense, bookID: entry.book?.id ?? entry.bookID).url) {
                        Label("Spesa", systemImage: "plus")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .foregroundStyle(theme.palette.onAccent)
                            .background(accent, in: Capsule())
                    }
                    .widgetAccentable()
                }
            }
            if let book = entry.book {
                summary(book).privacySensitive()
            } else {
                FinanceWidgetStateView(hidden: entry.snapshot.state == .hidden, tint: accent,
                                       compact: family == .systemSmall)
            }
        }
    }

    @ViewBuilder
    private func summary(_ book: WidgetBookSnapshot) -> some View {
        if family == .systemSmall {
            VStack(alignment: .leading, spacing: 4) {
                Spacer(minLength: 6)
                hero(book)
                Spacer(minLength: 6)
                if let budget = book.budget { BudgetBar(budget: budget, tint: tint(for: budget)) }
                caption(book)
            }
        } else {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Spacer(minLength: 6)
                    hero(book)
                    Spacer(minLength: 6)
                    if let budget = book.budget { BudgetBar(budget: budget, tint: tint(for: budget)) }
                    caption(book)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 8) {
                    Spacer(minLength: 6)
                    if book.budget != nil {
                        WidgetStat(title: "Spese del mese", value: book.monthSpent.formatted(.currency(code: book.currency)),
                                   icon: "calendar", tint: accent)
                    }
                    WidgetStat(title: "Scadenze in 7 giorni", value: "\(weekDueCount(book))",
                               icon: "calendar.badge.clock", tint: accent)
                    Spacer(minLength: 0)
                    FinanceWidgetFreshness(generatedAt: entry.snapshot.generatedAt, now: entry.date)
                }
                .frame(width: 128, alignment: .leading)
            }
        }
    }

    private func hero(_ book: WidgetBookSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(book.budget.map { $0.remaining < 0 ? "Oltre il budget" : "Restano" } ?? "Spese registrate")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Text(book.budget.map { abs($0.remaining) } ?? book.monthSpent, format: .currency(code: book.currency))
                .font(.system(family == .systemSmall ? .title2 : .title, design: .rounded, weight: .bold))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                .financeWidgetForeground(book.budget.map(tint(for:)) ?? .primary)
                .widgetAccentable()
        }
    }

    private func caption(_ book: WidgetBookSnapshot) -> some View {
        Group {
            if let budget = book.budget {
                Text("\(budget.name) · \(budget.spent.formatted(.currency(code: book.currency))) di \(budget.limit.formatted(.currency(code: book.currency)))")
            } else {
                Text(book.name)
            }
        }
        .font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
    }

    private func weekDueCount(_ book: WidgetBookSnapshot) -> Int {
        let end = Calendar.current.date(byAdding: .day, value: 7, to: entry.date) ?? entry.date
        return book.occurrenceDates.filter { $0 >= entry.date && $0 < end }.count
    }

    private func tint(for budget: WidgetBudgetSnapshot) -> Color {
        budget.remaining < 0 ? theme.palette.indicators.deficit : theme.palette.indicators.margin
    }
}

/// Spent share of the budget, with the overrun shown as a full deficit bar.
private struct BudgetBar: View {
    let budget: WidgetBudgetSnapshot
    let tint: Color
    @Environment(\.widgetRenderingMode) private var renderingMode
    private var share: Double {
        budget.limit > 0 ? min(1, NSDecimalNumber(decimal: budget.spent / budget.limit).doubleValue) : 1
    }
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(renderingMode == .fullColor ? 0.08 : 0.2))
                Capsule().fill(renderingMode == .fullColor ? tint : .primary)
                    .frame(width: max(6, proxy.size.width * share))
                    .widgetAccentable()
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

private struct WidgetStat: View {
    let title: LocalizedStringKey
    let value: String
    let icon: String
    let tint: Color
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.caption.weight(.semibold))
                .financeWidgetForeground(tint).frame(width: 16)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                Text(title).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#if os(iOS)
private struct FinanceLockScreenSummary: View {
    let entry: FinanceWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label { Text("Formi") } icon: { Image("FormiMark").resizable().widgetAccentedRenderingMode(.desaturated).scaledToFit().frame(width: 14, height: 14) }.font(.caption.weight(.semibold))
            if let book = entry.book {
                VStack(alignment: .leading, spacing: 1) {
                    Text(book.budget?.remaining ?? book.monthSpent, format: .currency(code: book.currency))
                        .font(.headline).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                    Text(book.budget.map { $0.remaining < 0 ? "Oltre il budget" : "Residuo budget" } ?? "Spese del mese")
                        .font(.caption2).lineLimit(1)
                }
                .privacySensitive()
            } else {
                Label(entry.snapshot.state == .hidden ? "Dati nascosti" : "Apri per aggiornare",
                      systemImage: entry.snapshot.state == .hidden ? "lock.fill" : "arrow.clockwise")
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif

@main
struct ForgiaWidgets: WidgetBundle {
    var body: some Widget {
        ForgiaOverviewWidget()
        FinanceBalanceWidget()
        FinanceUpcomingWidget()
    }
}

struct ForgiaOverviewWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: FinanceWidgetStorage.kind, intent: FinanceWidgetConfiguration.self, provider: FinanceWidgetProvider()) {
            FinanceWidgetView(entry: $0)
                .environment(\.financeWidgetTheme, FinanceWidgetAppearance.theme)
                .environment(\.locale, FinanceWidgetAppearance.locale)
        }
        .configurationDisplayName("Riepilogo Formi")
        .description("Budget residuo, spese del mese e scadenze per un libro.")
        #if os(iOS)
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryInline, .accessoryRectangular])
        #else
        .supportedFamilies([.systemSmall, .systemMedium])
        #endif
    }
}
