import AppIntents
import FinanceCore
import SwiftUI
import WidgetKit

struct FinanceUpcomingConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Prossime transazioni"
    @Parameter(title: "Libro") var book: WidgetBookEntity?
    static var parameterSummary: some ParameterSummary { Summary("Prossime transazioni di \(\.$book)") }
}

struct FinanceUpcomingEntry: TimelineEntry {
    let date: Date
    let snapshot: FinanceWidgetSnapshot
    let bookID: UUID?
    var book: WidgetBookSnapshot? {
        guard snapshot.usable(at: date) else { return nil }
        if let bookID { return snapshot.books.first { $0.id == bookID } }
        return snapshot.books.first
    }
    var transactions: [WidgetUpcomingTransaction] { book?.upcomingSchedule?.upcoming(at: date) ?? [] }
}

struct FinanceUpcomingProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> FinanceUpcomingEntry {
        FinanceUpcomingPreview.entry
    }
    func snapshot(for configuration: FinanceUpcomingConfiguration, in context: Context) async -> FinanceUpcomingEntry {
        context.isPreview ? FinanceUpcomingPreview.entry : entry(for: configuration)
    }
    func timeline(for configuration: FinanceUpcomingConfiguration, in context: Context) async -> Timeline<FinanceUpcomingEntry> {
        let entry = entry(for: configuration)
        let refresh = entry.date.addingTimeInterval(1800)
        guard entry.snapshot.usable(at: entry.date) else { return Timeline(entries: [entry], policy: .after(refresh)) }
        // Advance the next transaction even while the app is closed; also update the calendar at midnight.
        var dates = Set(entry.transactions.map(\.date).filter { $0 < entry.snapshot.validUntil })
        if let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: entry.date)),
           midnight < entry.snapshot.validUntil { dates.insert(midnight) }
        dates.insert(entry.snapshot.validUntil)
        let entries = [entry] + dates.sorted().map {
            FinanceUpcomingEntry(date: $0, snapshot: entry.snapshot, bookID: entry.bookID)
        }
        return Timeline(entries: entries, policy: .after(min(refresh, entry.snapshot.validUntil)))
    }
    private func entry(for configuration: FinanceUpcomingConfiguration) -> FinanceUpcomingEntry {
        FinanceUpcomingEntry(date: Date(), snapshot: FinanceWidgetStorage.read(from: FinanceWidgetStorage.sharedURL),
                             bookID: configuration.book?.id)
    }
}

struct FinanceUpcomingWidget: Widget {
    private var families: [WidgetFamily] {
        var result: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge]
        if #available(iOS 27.0, macOS 27.0, *) { result.append(.systemExtraLargePortrait) }
        #if os(iOS)
        result += [.accessoryInline, .accessoryCircular, .accessoryRectangular]
        #endif
        return result
    }
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: FinanceWidgetStorage.upcomingKind, intent: FinanceUpcomingConfiguration.self,
                               provider: FinanceUpcomingProvider()) {
            FinanceUpcomingWidgetView(entry: $0)
                .environment(\.financeWidgetTheme, FinanceWidgetAppearance.theme)
                .environment(\.locale, FinanceWidgetAppearance.locale)
        }
            .configurationDisplayName("Prossime transazioni")
            .description("La prossima giornata di spesa, la timeline e il calendario. Sulla schermata di blocco, la prossima spesa programmata.")
            .supportedFamilies(families)
    }
}

struct FinanceUpcomingWidgetView: View {
    let entry: FinanceUpcomingEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.financeWidgetTheme) private var theme
    private var tint: Color { theme.palette.indicators.calendar }
    private var portrait: Bool {
        if #available(iOS 27.0, macOS 27.0, *) { return family == .systemExtraLargePortrait }
        return false
    }
    private var accessory: Bool {
        #if os(iOS)
        return [.accessoryInline, .accessoryCircular, .accessoryRectangular].contains(family)
        #else
        return false
        #endif
    }
    var body: some View {
        Group {
            if accessory {
                #if os(iOS)
                UpcomingLockScreenContent(transaction: entry.transactions.first { $0.type == .expense },
                                          currency: entry.book?.currency ?? "EUR", family: family,
                                          available: entry.book?.upcomingSchedule != nil,
                                          hidden: entry.snapshot.state == .hidden)
                #endif
            } else {
                VStack(alignment: .leading, spacing: family == .systemSmall ? 8 : 12) {
                    UpcomingHeader(bookName: entry.book?.name, compact: family == .systemSmall)
                    if let book = entry.book, let schedule = book.upcomingSchedule {
                        if family == .systemSmall || family == .systemMedium {
                            UpcomingNextContent(transactions: entry.transactions, now: entry.date, currency: book.currency,
                                                coverageEnd: schedule.coverageEnd, compact: family == .systemSmall)
                        } else if portrait {
                            UpcomingCalendarContent(date: entry.date, transactions: entry.transactions)
                            Divider()
                            UpcomingTimelineContent(transactions: entry.transactions, currency: book.currency,
                                                    coverageEnd: schedule.coverageEnd, limit: 8)
                        } else if family == .systemExtraLarge {
                            HStack(alignment: .top, spacing: 24) {
                                UpcomingCalendarContent(date: entry.date, transactions: entry.transactions)
                                    .frame(maxWidth: .infinity)
                                Divider()
                                UpcomingTimelineContent(transactions: entry.transactions, currency: book.currency,
                                                        coverageEnd: schedule.coverageEnd, limit: 5)
                                    .frame(maxWidth: .infinity)
                            }
                        } else {
                            UpcomingTimelineContent(transactions: entry.transactions, currency: book.currency,
                                                    coverageEnd: schedule.coverageEnd, limit: 5)
                        }
                    } else {
                        FinanceWidgetStateView(hidden: entry.snapshot.state == .hidden, tint: tint,
                                               compact: family == .systemSmall)
                    }
                }
            }
        }
        .privacySensitive()
        .containerBackground(for: .widget) {
            if accessory { Color.clear } else { FinanceWidgetBackground(tint: tint) }
        }
        .widgetURL(FinanceWidgetRoute(destination: .planning, bookID: entry.book?.id ?? entry.bookID).url)
    }
}

private struct UpcomingHeader: View {
    @Environment(\.financeWidgetTheme) private var theme
    let bookName: String?
    let compact: Bool
    var body: some View {
        FinanceWidgetHeader(title: "Prossime", icon: "calendar.badge.clock",
                            tint: theme.palette.indicators.calendar, compact: compact) {
            if !compact, let bookName {
                Text(bookName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

private struct UpcomingNextContent: View {
    let transactions: [WidgetUpcomingTransaction]
    let now: Date
    let currency: String
    let coverageEnd: Date
    let compact: Bool
    @Environment(\.calendar) private var calendar

    var body: some View {
        if let summary = WidgetUpcomingDaySummary.next(in: transactions, at: now, calendar: calendar) {
            if compact {
                VStack(alignment: .leading, spacing: 5) {
                    UpcomingDueDate(date: summary.date, days: summary.daysUntilDue)
                        .font(.system(summary.daysUntilDue <= 7 ? .title2 : .headline, design: .rounded, weight: .bold))
                        .lineLimit(2).minimumScaleFactor(0.85)
                    UpcomingDayAmount(total: summary.total, type: summary.type, currency: currency)
                    UpcomingDayDescription(title: summary.transactions.count == 1 ? summary.transactions.first?.title : nil,
                                           count: summary.transactions.count, type: summary.type)
                    Spacer(minLength: 0)
                    UpcomingCategoryIcons(transactions: summary.categoryRepresentatives, limit: 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        UpcomingDueDate(date: summary.date, days: summary.daysUntilDue)
                            .font(.system(.largeTitle, design: .rounded, weight: .bold)).lineLimit(2).minimumScaleFactor(0.85)
                        if summary.daysUntilDue <= 7 {
                            Text(summary.date, format: .dateTime.day().month(.wide))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(summary.type == .expense ? "Da spendere" : "In entrata")
                            .font(.caption).foregroundStyle(.secondary)
                        UpcomingDayAmount(total: summary.total, type: summary.type, currency: currency)
                        UpcomingDayDescription(title: summary.transactions.count == 1 ? summary.transactions.first?.title : nil,
                                               count: summary.transactions.count, type: summary.type)
                        Spacer(minLength: 0)
                        UpcomingCategoryIcons(transactions: summary.categoryRepresentatives, limit: 4)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        } else {
            UpcomingEmptyContent(coverageEnd: coverageEnd)
        }
    }
}

private struct UpcomingDayAmount: View {
    let total: Decimal?
    let type: TransactionType
    let currency: String
    var body: some View {
        if let total {
            Text(type == .expense ? -total : total, format: .currency(code: currency))
                .font(.system(.title2, design: .rounded, weight: .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                .widgetAccentable()
        } else {
            Text("Importo da verificare").font(.subheadline.weight(.semibold))
        }
    }
}

private struct UpcomingDayDescription: View {
    let title: String?
    let count: Int
    let type: TransactionType
    var body: some View {
        Group {
            if let title, !title.isEmpty { Text(title) }
            else if count == 1 { Text(type == .expense ? "1 spesa programmata" : "1 entrata programmata") }
            else if type == .expense { Text("\(count) spese programmate") }
            else { Text("\(count) entrate programmate") }
        }
        .font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.85)
    }
}

private struct UpcomingDueDate: View {
    let date: Date
    let days: Int
    var body: some View {
        Group {
            switch days {
            case 0: Text("Oggi")
            case 1: Text("Domani")
            case 2...7: Text("Tra \(days) giorni")
            default: Text(date, format: .dateTime.day().month(.wide).year())
            }
        }
        .widgetAccentable()
    }
}

/// Category glyphs in the widget's own hue: the shapes carry the meaning, one colour keeps it calm.
private struct UpcomingCategoryIcons: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.financeWidgetTheme) private var theme
    let transactions: [WidgetUpcomingTransaction]
    let limit: Int
    var body: some View {
        let tint = theme.palette.indicators.calendar
        HStack(spacing: 6) {
            ForEach(Array(transactions.prefix(limit))) { transaction in
                Image(systemName: transaction.widgetIcon)
                    .widgetAccentedRenderingMode(.accented)
                    .font(.caption.weight(.semibold))
                    .financeWidgetForeground(tint)
                    .frame(width: 26, height: 26)
                    .background(renderingMode == .fullColor ? tint.opacity(0.14) : .clear,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityLabel(transaction.title)
            }
            if transactions.count > limit {
                Text("+\(transactions.count - limit)").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
    }
}

private struct UpcomingAmount: View {
    @Environment(\.financeWidgetTheme) private var theme
    let transaction: WidgetUpcomingTransaction
    let currency: String
    var body: some View {
        Group {
            if let amount = transaction.amount {
                Text(transaction.type == .income ? amount : -amount, format: .currency(code: currency))
            } else { Text("Importo non disponibile") }
        }
        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
        .financeWidgetForeground(transaction.type == .income ? theme.palette.indicators.margin : .primary)
        .widgetAccentable()
    }
}

private struct UpcomingEmptyContent: View {
    let coverageEnd: Date
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Spacer(minLength: 0)
            Label("Nessuna transazione programmata", systemImage: "calendar.badge.checkmark").font(.subheadline)
            Text("Fino al \(coverageEnd, format: .dateTime.day().month())").font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }
}

private struct UpcomingTimelineContent: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.financeWidgetTheme) private var theme
    let transactions: [WidgetUpcomingTransaction]
    let currency: String
    let coverageEnd: Date
    let limit: Int
    var body: some View {
        if transactions.isEmpty {
            UpcomingEmptyContent(coverageEnd: coverageEnd)
        } else {
            let tint = theme.palette.indicators.calendar
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(transactions.prefix(limit))) { transaction in
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: transaction.widgetIcon)
                            .widgetAccentedRenderingMode(.accented)
                            .font(.caption.weight(.semibold))
                            .financeWidgetForeground(tint)
                            .frame(width: 28, height: 28)
                            .background(renderingMode == .fullColor ? tint.opacity(0.14) : Color.primary.opacity(0.1),
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(transaction.title.isEmpty ? (transaction.type == .income ? "Entrata" : "Spesa") : transaction.title)
                                .font(.subheadline.weight(.medium)).lineLimit(1)
                            Text(transaction.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        UpcomingAmount(transaction: transaction, currency: currency)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    }
                    .accessibilityElement(children: .combine)
                }
                Spacer(minLength: 0)
                if transactions.count > limit {
                    Text("Altre \(transactions.count - limit) in programma").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct UpcomingCalendarContent: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.financeWidgetTheme) private var theme
    let date: Date
    let transactions: [WidgetUpcomingTransaction]
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    var body: some View {
        if let month = calendar.dateInterval(of: .month, for: date),
           let days = calendar.range(of: .day, in: .month, for: date) {
            let offset = (calendar.component(.weekday, from: month.start) - calendar.firstWeekday + 7) % 7
            let markedDays = Dictionary(grouping: transactions.filter { month.contains($0.date) && $0.date < month.end }) {
                calendar.component(.day, from: $0.date)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(date, format: .dateTime.month(.wide).year()).font(.headline)
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(0..<7, id: \.self) { index in
                        let weekday = (calendar.firstWeekday - 1 + index) % 7
                        Text(calendar.veryShortStandaloneWeekdaySymbols[weekday])
                            .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    ForEach(0..<(offset + days.count), id: \.self) { index in
                        if index < offset {
                            Color.clear.frame(height: 28).accessibilityHidden(true)
                        } else {
                            let day = index - offset + 1
                            let today = calendar.component(.day, from: date) == day
                            VStack(spacing: 3) {
                                Text(day.formatted(.number.locale(locale))).font(.caption.weight(today ? .bold : .regular))
                                Circle().fill(markedDays[day] == nil ? Color.clear : (renderingMode == .fullColor ? theme.palette.indicators.calendar : .primary))
                                    .frame(width: renderingMode == .fullColor ? 4 : 5, height: renderingMode == .fullColor ? 4 : 5)
                                    .widgetAccentable()
                            }
                            .frame(maxWidth: .infinity, minHeight: 28)
                            .background(today && renderingMode == .fullColor ? theme.palette.indicators.calendar.opacity(0.16) : .clear,
                                        in: RoundedRectangle(cornerRadius: 8))
                            .overlay {
                                if today && renderingMode != .fullColor {
                                    RoundedRectangle(cornerRadius: 8).strokeBorder(.primary, lineWidth: 1)
                                }
                            }
                            .accessibilityLabel(markedDays[day] != nil ? "\(day), transazioni programmate" : "\(day)")
                        }
                    }
                }
                Label("Movimenti programmati", systemImage: "circle.fill")
                    .font(.caption2).financeWidgetForeground(theme.palette.indicators.calendar)
            }
        }
    }
}

#if os(iOS)
private struct UpcomingLockScreenContent: View {
    let transaction: WidgetUpcomingTransaction?
    let currency: String
    let family: WidgetFamily
    let available: Bool
    let hidden: Bool
    var body: some View {
        if let transaction {
            switch family {
            case .accessoryInline:
                Label {
                    Text("\(transaction.title.isEmpty ? String(localized: "Spesa") : transaction.title) · \(transaction.date, format: .dateTime.day().month())")
                } icon: { Image(systemName: transaction.widgetIcon) }
            case .accessoryCircular:
                VStack(spacing: 2) {
                    Image(systemName: transaction.widgetIcon).font(.caption)
                    Text(transaction.date, format: .dateTime.day()).font(.title2.bold())
                    Text(transaction.date, format: .dateTime.month(.abbreviated)).font(.caption2)
                }
                .accessibilityLabel("Prossima spesa: \(transaction.title), \(transaction.date, format: .dateTime.day().month())")
            default:
                VStack(alignment: .leading, spacing: 2) {
                    Label(transaction.title.isEmpty ? String(localized: "Prossima spesa") : transaction.title,
                          systemImage: transaction.widgetIcon).font(.headline).lineLimit(1)
                    UpcomingAmount(transaction: transaction, currency: currency).font(.subheadline.weight(.semibold))
                    Text(transaction.date, format: .dateTime.day().month().hour().minute()).font(.caption2).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Label(hidden ? "Dati nascosti" : (available ? "Nessuna spesa prossima" : "Apri Formi"),
                  systemImage: hidden ? "lock.fill" : "calendar")
                .font(.caption)
        }
    }
}
#endif


private extension WidgetUpcomingTransaction {
    var widgetIcon: String {
        guard let icon = categoryIcon?.trimmingCharacters(in: .whitespacesAndNewlines), !icon.isEmpty else { return type.icon }
        return icon
    }
}

/// Gallery previews use the shared synthetic snapshot, never the user's data.
private enum FinanceUpcomingPreview {
    static var entry: FinanceUpcomingEntry {
        FinanceUpcomingEntry(date: Date(), snapshot: FinanceWidgetSample.snapshot, bookID: FinanceWidgetSample.bookID)
    }
}

#Preview("Prossima · small", as: .systemSmall) {
    FinanceUpcomingWidget()
} timeline: {
    FinanceUpcomingPreview.entry
}

#Preview("Prossima · medium", as: .systemMedium) {
    FinanceUpcomingWidget()
} timeline: {
    FinanceUpcomingPreview.entry
}

#Preview("Timeline", as: .systemLarge) {
    FinanceUpcomingWidget()
} timeline: {
    FinanceUpcomingPreview.entry
}

#Preview("Calendario e timeline", as: .systemExtraLarge) {
    FinanceUpcomingWidget()
} timeline: {
    FinanceUpcomingPreview.entry
}

#if os(iOS)
#Preview("Prossima spesa · lockscreen", as: .accessoryRectangular) {
    FinanceUpcomingWidget()
} timeline: {
    FinanceUpcomingPreview.entry
}
#endif
