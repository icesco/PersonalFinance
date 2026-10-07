import SwiftUI
import FinanceCore

/// Day nodes connected using their layout anchors, as in Monstera's care timeline.
/// The axis ends at the final node and adapts to multiline text and Dynamic Type.
struct FinanceSpendingTimeline: View {
    let events: [FinanceCalendarEvent]
    let transactions: [FinanceCore.Transaction]
    let currency: String
    let interval: DateInterval
    let locale: Locale
    var pinnedDate: Date? = nil

    var body: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let byDay = Dictionary(grouping: events) { calendar.startOfDay(for: $0.date) }
        let days = Set(byDay.keys).union(today >= interval.start && today < interval.end ? [today] : []).sorted()
        VStack(alignment: .leading, spacing: 0) {
            ForEach(days, id: \.self) { day in
                FinanceTimelineDayHeader(date: day, locale: locale, isToday: day == today)
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(key: FinanceTimelineHeaderPositions.self,
                                value: [day: geometry.frame(in: .named("finance-calendar-scroll")).minY])
                        }
                    }
                    .opacity(pinnedDate == day ? 0 : 1)
                    .accessibilityHidden(pinnedDate == day)
                FinanceTimelineDay(date: day, events: byDay[day] ?? [], transactions: transactions,
                    currency: currency, locale: locale, isToday: day == today)
                    .padding(.bottom, 24)
            }
        }
        .backgroundPreferenceValue(FinanceTimelineNodeAnchors.self) { anchors in
            GeometryReader { geometry in
                let points = anchors.values.map { anchor in
                    let bounds = geometry[anchor]
                    return CGPoint(x: bounds.midX, y: bounds.midY)
                }.sorted { $0.y < $1.y }
                Path { path in
                    if let first = points.first, let last = points.last, points.count > 1 {
                        path.move(to: first)
                        path.addLine(to: last)
                    }
                }
                .stroke(LinearGradient(colors: [ForgiaPalette.spending.opacity(0.45), ForgiaPalette.calendar.opacity(0.35)],
                    startPoint: .top, endPoint: .bottom), style: StrokeStyle(lineWidth: 1.5, dash: [2, 5]))
            }.accessibilityHidden(true).allowsHitTesting(false)
        }
        .accessibilityIdentifier("finance-spending-timeline")
    }
}

private struct FinanceTimelineNodeAnchors: PreferenceKey {
    static var defaultValue: [Date: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [Date: Anchor<CGRect>], nextValue: () -> [Date: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

struct FinanceTimelineHeaderPositions: PreferenceKey {
    static var defaultValue: [Date: CGFloat] { [:] }
    static func reduce(value: inout [Date: CGFloat], nextValue: () -> [Date: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

struct FinanceTimelineDayHeader: View {
    let date: Date
    let locale: Locale
    let isToday: Bool
    var isPinned = false
    private var isFuture: Bool { date > Calendar.current.startOfDay(for: Date()) }
    private var tint: Color { isFuture || isToday ? ForgiaPalette.calendar : ForgiaPalette.spending }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle().fill(tint.opacity(isToday ? 0.16 : 0.08)).frame(width: 28, height: 28)
                    Circle().fill(isFuture ? ForgiaPalette.canvas : tint)
                        .overlay { Circle().strokeBorder(tint, lineWidth: 2) }
                        .frame(width: isToday ? 12 : 8, height: isToday ? 12 : 8)
                }
                .frame(width: 28, height: 34)
                .anchorPreference(key: FinanceTimelineNodeAnchors.self, value: .bounds) { [date: $0] }
                .accessibilityHidden(true)
                Text(date.formatted(.dateTime.day().locale(locale)))
                    .font(.system(.largeTitle, design: .serif, weight: .semibold))
                    .foregroundStyle(tint).monospacedDigit()
                VStack(alignment: .leading, spacing: 3) {
                    Text(date.formatted(.dateTime.weekday(.wide).locale(locale)))
                        .font(.subheadline.weight(.semibold)).foregroundStyle(tint)
                    Text(date.formatted(.dateTime.month(.wide).locale(locale)))
                        .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                }
                Spacer(minLength: 4)
                if isToday {
                    Text("Oggi").font(.caption.weight(.semibold)).foregroundStyle(tint)
                        .padding(.horizontal, 11).padding(.vertical, 6)
                        .background(tint.opacity(0.12), in: Capsule())
                } else if isFuture {
                    let distance = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: date).day ?? 0
                    Text("Tra \(distance) giorni").font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                        .multilineTextAlignment(.trailing)
                }
            }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("finance-timeline-\(isPinned ? "pinned-header" : "header")-\(Calendar.current.component(.day, from: date))")
    }
}

private struct FinanceTimelineDay: View {
    let date: Date
    let events: [FinanceCalendarEvent]
    let transactions: [FinanceCore.Transaction]
    let currency: String
    let locale: Locale
    let isToday: Bool
    private var isFuture: Bool { date > Calendar.current.startOfDay(for: Date()) }
    private var tint: Color { isFuture || isToday ? ForgiaPalette.calendar : ForgiaPalette.spending }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 10) {
                if events.isEmpty && isToday {
                    Text("Da qui iniziano le prossime scadenze")
                        .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(events) { event in
                    if let transaction = transactions.first(where: { $0.id == event.transactionID }) {
                        NavigationLink {
                            TransactionDetailView(transaction: transaction)
                        } label: {
                            FinanceTimelineEventCard(event: event, currency: currency, category: transaction.category)
                        }.buttonStyle(.plain)
                    } else {
                        FinanceTimelineEventCard(event: event, currency: currency)
                    }
                }
            }.padding(.leading, 42)
        }
    }
}

private struct FinanceTimelineEventCard: View {
    let event: FinanceCalendarEvent
    let currency: String
    var category: FinanceCore.Category? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.tintedBackgrounds) private var tintedBackgrounds
    private var tint: Color {
        event.kind != .recorded ? ForgiaPalette.calendar : event.type == .income ? ForgiaPalette.margin : ForgiaPalette.spending
    }
    private var icon: String {
        event.kind == .recurrence ? "arrow.trianglehead.2.clockwise.rotate.90" : event.kind == .planned ? "clock" : event.type == .income ? "arrow.down.left" : "arrow.up.right"
    }
    private var categoryIcon: String {
        guard let icon = category?.icon, !icon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "tag" }
        return icon
    }
    private var status: LocalizedStringKey {
        event.kind == .recorded ? "Registrato" : event.kind == .planned ? "Programmato" : event.date <= Date() ? "Da registrare" : "Ricorrenza prevista"
    }
    private var valueLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: categoryIcon)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(tint).frame(width: 40, height: 40)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    if let name = category?.name, !name.isEmpty {
                        Text(name).font(.caption.weight(.semibold)).foregroundStyle(tint)
                    }
                    Label(status, systemImage: icon).font(.caption2).foregroundStyle(ForgiaPalette.mutedText)
                }
                Spacer(minLength: 4)
                if event.kind == .recorded {
                    Text(event.date, format: .dateTime.hour().minute())
                        .font(.caption.monospacedDigit()).foregroundStyle(ForgiaPalette.mutedText)
                }
            }
            valueLayout {
                Text(event.title).font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
                if let amount = event.amount {
                    Text(amount, format: .currency(code: currency))
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .foregroundStyle(tint).monospacedDigit().financeNumericMotion(amount)
                        .lineLimit(1).minimumScaleFactor(0.75)
                } else {
                    Label("Importo da verificare", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                }
            }
            if event.kind == .recurrence {
                Label("Apri il movimento originale", systemImage: "arrow.turn.up.right")
                    .font(.caption2).foregroundStyle(ForgiaPalette.mutedText)
            }
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 24).fill(ForgiaPalette.surface)
                .overlay {
                    if tintedBackgrounds {
                        RoundedRectangle(cornerRadius: 24).fill(LinearGradient(
                            colors: [tint.opacity(0.10), tint.opacity(0.025)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(tint.opacity(0.22), style: StrokeStyle(lineWidth: 0.75, dash: event.kind == .recorded ? [] : [5, 5]))
        }
        .shadow(color: tint.opacity(0.07), radius: 10, y: 5)
        .accessibilityElement(children: .combine)
        .financeCardEntrance()
    }
}
