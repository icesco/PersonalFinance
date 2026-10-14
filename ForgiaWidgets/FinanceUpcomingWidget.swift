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
    private var tint: Color { theme.palette.accent }
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
                    UpcomingHeader(compact: family == .systemSmall)
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
            if accessory { Color.clear } else { FinanceWidgetBackground() }
        }
        .widgetURL(FinanceWidgetRoute(destination: .planning, bookID: entry.book?.id ?? entry.bookID).url)
    }
}

private struct UpcomingHeader: View {
    @Environment(\.financeWidgetTheme) private var theme
    let compact: Bool
    var body: some View {
        FinanceWidgetHeader(title: "Prossime", icon: "calendar.badge.clock",
                            tint: theme.palette.accent, compact: compact)
    }
}

private struct UpcomingNextContent: View {
    let transactions: [WidgetUpcomingTransaction]
    let now: Date
    let currency: String
    let coverageEnd: Date
    let compact: Bool
    @Environment(\.calendar) private var calendar
    @Environment(\.financeWidgetTheme) private var theme

    var body: some View {
        if let summary = WidgetUpcomingDaySummary.next(in: transactions, at: now, calendar: calendar) {
            if compact {
                VStack(alignment: .leading, spacing: 5) {
                    UpcomingDueDate(date: summary.date, days: summary.daysUntilDue)
                        .font(.system(summary.daysUntilDue <= 7 ? .title2 : .headline, weight: .semibold))
                        .lineLimit(2).minimumScaleFactor(0.85)
                    UpcomingDayAmount(total: summary.total, type: summary.type, currency: currency)
                    UpcomingDayDescription(title: summary.transactions.count == 1 ? summary.transactions.first?.title : nil,
                                           count: summary.transactions.count, type: summary.type)
                    Spacer(minLength: 0)
                    UpcomingCategoryIcons(transactions: summary.categoryRepresentatives, limit: 3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        UpcomingDueDate(date: summary.date, days: summary.daysUntilDue)
                            .font(.system(.largeTitle, weight: .semibold)).lineLimit(2).minimumScaleFactor(0.85)
                        if summary.daysUntilDue <= 7 {
                            Text(summary.date, format: .dateTime.day().month(.wide))
                                .font(.caption).financeWidgetForeground(theme.palette.mutedText).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(summary.type == .expense ? "Da spendere" : "In entrata")
                            .font(.caption).financeWidgetForeground(theme.palette.mutedText)
                        UpcomingDayAmount(total: summary.total, type: summary.type, currency: currency)
                        UpcomingDayDescription(title: summary.transactions.count == 1 ? summary.transactions.first?.title : nil,
                                               count: summary.transactions.count, type: summary.type)
                        Spacer(minLength: 0)
                        UpcomingCategoryIcons(transactions: summary.categoryRepresentatives, limit: 3)
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
                .font(.system(.title2, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(.primary)
        } else {
            Text("Importo da verificare").font(.subheadline.weight(.semibold))
        }
    }
}

private struct UpcomingDayDescription: View {
    @Environment(\.financeWidgetTheme) private var theme
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
        .font(.caption).financeWidgetForeground(theme.palette.mutedText).lineLimit(1).minimumScaleFactor(0.85)
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

private struct UpcomingCategoryIcons: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.financeWidgetTheme) private var theme
    let transactions: [WidgetUpcomingTransaction]
    let limit: Int
    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(transactions.prefix(limit))) { transaction in
                let tint = transaction.widgetTint(fallback: theme.palette.accent)
                Image(systemName: transaction.widgetIcon)
                    .widgetAccentedRenderingMode(.accented)
                    .font(.subheadline.weight(.semibold))
                    .financeWidgetForeground(tint)
                    .frame(width: 32, height: 32)
                    .background(renderingMode == .fullColor ? tint.opacity(0.14) : .clear,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityLabel(transaction.title)
            }
            if transactions.count > limit {
                Text("+\(transactions.count - limit)").font(.caption2.weight(.semibold)).financeWidgetForeground(theme.palette.mutedText)
            }
        }
    }
}

private struct UpcomingAmount: View {
    let transaction: WidgetUpcomingTransaction
    let currency: String
    var body: some View {
        Group {
            if let amount = transaction.amount {
                Text(transaction.type == .income ? amount : -amount, format: .currency(code: currency))
            } else { Text("Importo non disponibile") }
        }
        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
        .foregroundStyle(.primary)
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
    let transactions: [WidgetUpcomingTransaction]
    let currency: String
    let coverageEnd: Date
    let limit: Int
    var body: some View {
        if transactions.isEmpty {
            UpcomingEmptyContent(coverageEnd: coverageEnd)
        } else {
            ViewThatFits(in: .vertical) {
                rows(limit: limit)
                rows(limit: max(1, limit - 1))
                rows(limit: max(1, limit - 2))
                rows(limit: max(1, limit / 2))
                rows(limit: 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func rows(limit: Int) -> some View {
        UpcomingTimelineRows(transactions: Array(transactions.prefix(limit)),
                             remainingCount: max(0, transactions.count - limit), currency: currency)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct UpcomingTimelineNodeAnchors: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private struct UpcomingTimelineRows: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.financeWidgetTheme) private var theme
    let transactions: [WidgetUpcomingTransaction]
    let remainingCount: Int
    let currency: String

    var body: some View {
        let tint = theme.palette.accent
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(transactions) { transaction in
                    let categoryTint = transaction.widgetTint(fallback: tint)
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: transaction.widgetIcon)
                            .widgetAccentedRenderingMode(.accented)
                            .font(.title3.weight(.semibold))
                            .financeWidgetForeground(categoryTint)
                            .frame(width: 42, height: 42)
                            .background {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(renderingMode == .fullColor ? theme.palette.surface : Color.clear)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(renderingMode == .fullColor ? categoryTint.opacity(0.14) : Color.primary.opacity(0.1))
                                    }
                            }
                            .anchorPreference(key: UpcomingTimelineNodeAnchors.self, value: .bounds) { [transaction.id: $0] }
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(transaction.title.isEmpty ? (transaction.type == .income ? "Entrata" : "Spesa") : transaction.title)
                                .font(.headline).lineLimit(2)
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(transaction.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                                    .font(.caption).financeWidgetForeground(theme.palette.mutedText).lineLimit(1)
                                Spacer(minLength: 0)
                                UpcomingAmount(transaction: transaction, currency: currency)
                                    .font(.title3.weight(.semibold))
                                    .layoutPriority(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .backgroundPreferenceValue(UpcomingTimelineNodeAnchors.self) { anchors in
                GeometryReader { geometry in
                    let centers = anchors.values.map { anchor in
                        let bounds = geometry[anchor]
                        return CGPoint(x: bounds.midX, y: bounds.midY)
                    }.sorted { $0.y < $1.y }
                    Path { path in
                        if centers.count > 1, let first = centers.first, let last = centers.last {
                            path.move(to: first)
                            path.addLine(to: last)
                        }
                    }
                    .stroke(renderingMode == .fullColor ? tint.opacity(0.45) : Color.primary.opacity(0.45),
                            style: StrokeStyle(lineWidth: 1.5, dash: [2, 5]))
                }
                .accessibilityHidden(true)
                .allowsHitTesting(false)
            }
            if remainingCount > 0 {
                Text("Altre \(remainingCount) in programma")
                    .font(.caption).financeWidgetForeground(theme.palette.mutedText)
                    .padding(.leading, 54)
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
                                Circle().fill(markedDays[day] == nil ? Color.clear : (renderingMode == .fullColor ? theme.palette.accent : .primary))
                                    .frame(width: renderingMode == .fullColor ? 4 : 5, height: renderingMode == .fullColor ? 4 : 5)
                                    .widgetAccentable()
                            }
                            .frame(maxWidth: .infinity, minHeight: 28)
                            .background(today && renderingMode == .fullColor ? theme.palette.accent.opacity(0.16) : .clear,
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
                    .font(.caption2).financeWidgetForeground(theme.palette.accent)
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
    func widgetTint(fallback: Color) -> Color {
        FinanceCategoryColor.color(hex: categoryColor, fallback: fallback)
    }

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
