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
    static let title: LocalizedStringResource = "Riepilogo Forgia"
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
        entry(for: configuration)
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
    private let accent = Color(red: 0.75, green: 0.36, blue: 0.16)

    var body: some View {
        Group {
            #if os(iOS)
            switch family {
            case .accessoryCircular:
                VStack(spacing: 2) {
                    Image(systemName: "plus").font(.title2.bold())
                    Text("Spesa").font(.caption2)
                }
                .accessibilityLabel("Aggiungi una spesa in Forgia")
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
        .containerBackground(.background, for: .widget)
        .widgetURL(FinanceWidgetRoute(destination: destination, bookID: entry.book?.id ?? entry.bookID).url)
    }

    private var destination: FinanceWidgetRoute.Destination {
        #if os(iOS)
        if family == .accessoryCircular || family == .accessoryInline { return .expense }
        #endif
        return entry.snapshot.state == .hidden ? .expense : .planning
    }

    private var homeSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Forgia", systemImage: "flame.fill").font(.caption.weight(.semibold)).foregroundStyle(accent)
                Spacer()
                if family != .systemSmall {
                    Link(destination: FinanceWidgetRoute(destination: .expense, bookID: entry.book?.id ?? entry.bookID).url) {
                        Label("Spesa", systemImage: "plus.circle.fill").font(.caption.weight(.semibold))
                    }
                }
            }
            if let book = entry.book {
                summary(book).privacySensitive()
            } else {
                Spacer(minLength: 0)
                Label(entry.snapshot.state == .hidden ? "Dati nascosti" : "Apri Forgia", systemImage: entry.snapshot.state == .hidden ? "lock.fill" : "arrow.clockwise")
                    .font(.headline)
                Text(entry.snapshot.state == .hidden ? (family == .systemSmall ? "Gestisci in Forgia" : "Gestisci la visibilità nelle impostazioni.") : "Aggiorna nell’app.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(entry.snapshot.state == .hidden ? "Nuova spesa" : "Apri il riepilogo").font(.caption2).foregroundStyle(accent)
            }
        }
    }

    private func summary(_ book: WidgetBookSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(book.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            if let budget = book.budget {
                Text(budget.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(budget.remaining, format: .currency(code: book.currency))
                    .font(.title2.bold()).minimumScaleFactor(0.6).lineLimit(1)
                    .foregroundStyle(budget.remaining < 0 ? .red : .primary)
                Text(budget.remaining < 0 ? "Oltre il budget" : (family == .systemSmall ? "Residuo registrato" : "Residuo budget registrato")).font(.caption2)
            } else {
                Text(book.monthSpent, format: .currency(code: book.currency))
                    .font(.title2.bold()).minimumScaleFactor(0.6).lineLimit(1)
                Text("Spese registrate nel mese").font(.caption2)
            }
            if family != .systemSmall {
                let end = Calendar.current.date(byAdding: .day, value: 7, to: entry.date) ?? entry.date
                let count = book.occurrenceDates.filter { $0 >= entry.date && $0 < end }.count
                HStack {
                    if book.budget != nil {
                        Text("Mese: \(book.monthSpent.formatted(.currency(code: book.currency)))")
                    }
                    Spacer(minLength: 4)
                    Text("\(count) scadenze · 7 giorni")
                }.font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Text("Al \(entry.snapshot.generatedAt.formatted(.dateTime.day().month().hour().minute()))")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

#if os(iOS)
private struct FinanceLockScreenSummary: View {
    let entry: FinanceWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Forgia", systemImage: "flame.fill").font(.caption.weight(.semibold))
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
    var body: some Widget { ForgiaOverviewWidget() }
}

struct ForgiaOverviewWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: FinanceWidgetStorage.kind, intent: FinanceWidgetConfiguration.self, provider: FinanceWidgetProvider()) {
            FinanceWidgetView(entry: $0)
        }
        .configurationDisplayName("Riepilogo Forgia")
        .description("Budget residuo, spese del mese e scadenze per un libro.")
        #if os(iOS)
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryInline, .accessoryRectangular])
        #else
        .supportedFamilies([.systemSmall, .systemMedium])
        #endif
    }
}
