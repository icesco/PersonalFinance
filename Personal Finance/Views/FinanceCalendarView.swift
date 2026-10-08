import SwiftUI
import SwiftData
import FinanceCore
import FinanceUICalendar

// Preserve the preferred language even when the app has no localized resource bundle yet.
private var financeCalendarLocale: Locale {
    Locale(identifier: Locale.preferredLanguages.first ?? Locale.current.identifier)
}

struct FinanceCalendarView: View {
    let contoIDs: Set<UUID>
    let currency: String
    @Query private var transactions: [FinanceCore.Transaction]
    @Query private var resolutions: [RecurrenceResolution]
    @State private var month: Date
    @State private var selectedDate: Date
    @State private var timeline = false
    @State private var pinnedTimelineDate: Date?
    @State private var expensesOnly = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var displayCalendar: Calendar {
        var calendar = Calendar.current
        calendar.locale = financeCalendarLocale
        return calendar
    }

    init(contoIDs: Set<UUID>, currency: String, initialDate: Date = Date()) {
        self.contoIDs = contoIDs
        self.currency = currency
        _month = State(initialValue: initialDate)
        _selectedDate = State(initialValue: Calendar.current.startOfDay(for: initialDate))
    }

    var body: some View {
        let now = Date()
        let interval = Calendar.current.dateInterval(of: .month, for: month)!
        let calendarEvents = FinanceCalendarEvents.build(transactions: transactions, resolutions: resolutions,
            contoIDs: contoIDs, interval: interval, now: now).filter { !expensesOnly || $0.type == .expense }
        let events = timeline ? FinanceCalendarEvents.upcoming(calendarEvents, now: now) : calendarEvents
        let byDay = Dictionary(grouping: events) { Calendar.current.startOfDay(for: $0.date) }
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("Vista", selection: $timeline) {
                    Text("Calendario").tag(false)
                    Text("Timeline").tag(true)
                }.pickerStyle(.segmented).accessibilityIdentifier("finance-calendar-mode")
                Toggle("Solo spese", isOn: $expensesOnly).tint(ForgiaPalette.accent).accessibilityIdentifier("finance-calendar-expenses")
                if timeline {
                    FinanceTimelineMonthHeader(month: $month)
                } else {
                    MonthlyCalendarView(selectedDate: $selectedDate, currentMonth: $month,
                        palette: .init(accent: ForgiaPalette.accent, foreground: .primary, foregroundSecondary: ForgiaPalette.mutedText), calendar: displayCalendar) { date in
                        (byDay[Calendar.current.startOfDay(for: date)] ?? []).map { event in
                            CalendarTask(id: event.id, categoryID: event.kind == .recorded ? "recorded" : "scheduled",
                                categoryLabel: event.kind == .recorded ? "Registrato" : "Previsto", categoryIcon: "circle",
                                categoryColor: event.kind == .recorded ? ForgiaPalette.spending : ForgiaPalette.calendar, title: event.title)
                        }
                    }.unifiedCard()
                }
                HStack(spacing: 18) {
                    if !timeline {
                        Label("Registrato", systemImage: "circle.fill").foregroundStyle(ForgiaPalette.spending)
                    }
                    Label(timeline ? "Previsto" : "Previsto / da registrare", systemImage: "circle.fill").foregroundStyle(ForgiaPalette.calendar)
                }.font(.caption)
                Button("Torna a oggi") { month = Date(); selectedDate = Calendar.current.startOfDay(for: Date()) }
                    .accessibilityIdentifier("finance-calendar-today")
                FinanceCalendarSummary(events: events, currency: currency, upcomingOnly: timeline)
                if timeline {
                    if events.isEmpty {
                        ContentUnavailableView(expensesOnly ? "Nessuna spesa futura nel mese" : "Nessun movimento futuro nel mese", systemImage: "calendar")
                    } else {
                        FinanceSpendingTimeline(events: events, transactions: transactions, currency: currency,
                            interval: interval, locale: financeCalendarLocale, pinnedDate: pinnedTimelineDate)
                    }
                } else {
                    FinanceCalendarDaySection(date: selectedDate, events: byDay[selectedDate] ?? [], transactions: transactions, currency: currency)
                }
                Text(timeline
                    ? "La timeline mostra solo movimenti programmati e ricorrenze con una data futura. Non include spese non programmate. I trasferimenti tra conti sono esclusi."
                    : "Le previsioni comprendono solo movimenti futuri e ricorrenze ancora da registrare. Non includono spese non programmate. I trasferimenti tra conti sono esclusi.")
                    .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
            }.frame(maxWidth: 760).frame(maxWidth: .infinity).padding(22)
        }
        .coordinateSpace(name: "finance-calendar-scroll")
        .onPreferenceChange(FinanceTimelineHeaderPositions.self) { positions in
            let activeDate = positions.filter { $0.value <= 0 }.keys.max()
            if pinnedTimelineDate != activeDate { pinnedTimelineDate = activeDate }
        }
        .safeAreaBar(edge: .top, spacing: 0) {
            if timeline, let pinnedTimelineDate {
                FinanceTimelineDayHeader(date: pinnedTimelineDate, locale: financeCalendarLocale,
                    isToday: Calendar.current.isDateInToday(pinnedTimelineDate), isPinned: true)
                    .frame(maxWidth: 760).frame(maxWidth: .infinity)
                    .padding(.horizontal, 22)
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .themedBackground()
        .navigationTitle("Calendario e timeline")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        #endif
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: selectedDate)
        .onChange(of: month) {
            pinnedTimelineDate = nil
            if !Calendar.current.isDate(selectedDate, equalTo: month, toGranularity: .month) {
                selectedDate = Calendar.current.dateInterval(of: .month, for: month)!.start
            }
        }
        .onChange(of: timeline) { pinnedTimelineDate = nil }
    }
}

private struct FinanceTimelineMonthHeader: View {
    @Binding var month: Date
    var body: some View {
        HStack {
            Button("Mese precedente", systemImage: "chevron.left") { month = Calendar.current.date(byAdding: .month, value: -1, to: month)! }
                .labelStyle(.iconOnly).frame(width: 44, height: 44)
            Spacer()
            Text(month.formatted(.dateTime.month(.wide).year().locale(financeCalendarLocale))).font(.headline).foregroundStyle(ForgiaPalette.calendar)
            Spacer()
            Button("Mese successivo", systemImage: "chevron.right") { month = Calendar.current.date(byAdding: .month, value: 1, to: month)! }
                .labelStyle(.iconOnly).frame(width: 44, height: 44)
        }.buttonStyle(.plain)
    }
}

private struct FinanceCalendarSummary: View {
    let events: [FinanceCalendarEvent]
    let currency: String
    var upcomingOnly = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(upcomingOnly ? "Spese future del mese" : "Spese del mese").font(.headline).foregroundStyle(ForgiaPalette.calendar)
            let expenses = events.filter { $0.type == .expense }
            let recorded = expenses.filter { $0.kind == .recorded }
            let future = expenses.filter { $0.kind != .recorded && $0.date > Date() }
            if !upcomingOnly {
                FinanceCalendarTotal(title: "Registrate", events: recorded, currency: currency)
            }
            FinanceCalendarTotal(title: "In arrivo", events: future, currency: currency)
            let pending = expenses.filter { $0.kind == .recurrence && $0.date <= Date() }
            if !upcomingOnly && !pending.isEmpty {
                FinanceCalendarTotal(title: "Scadenze da registrare", events: pending, currency: currency)
            }
        }.unifiedCard()
    }
}

private struct FinanceCalendarTotal: View {
    let title: LocalizedStringKey
    let events: [FinanceCalendarEvent]
    let currency: String
    var body: some View {
        HStack {
            Text(title).foregroundStyle(ForgiaPalette.mutedText)
            Spacer()
            if events.contains(where: { $0.amount == nil }) {
                Text("Importi da verificare").font(.caption)
            } else {
                let total = events.reduce(Decimal.zero) { $0 + ($1.amount ?? 0) }
                Text(total, format: .currency(code: currency)).monospacedDigit().financeNumericMotion(total).foregroundStyle(ForgiaPalette.calendar)
            }
        }.font(.subheadline)
    }
}

private struct FinanceCalendarDaySection: View {
    let date: Date
    let events: [FinanceCalendarEvent]
    let transactions: [FinanceCore.Transaction]
    let currency: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(financeCalendarLocale))).font(.headline)
            if events.isEmpty {
                Text("Nessun movimento per questo giorno").foregroundStyle(ForgiaPalette.mutedText)
            }
            ForEach(events) { event in
                if let transaction = transactions.first(where: { $0.id == event.transactionID }) {
                    NavigationLink {
                        TransactionDetailView(transaction: transaction)
                    } label: {
                        FinanceCalendarEventRow(event: event, currency: currency)
                    }.buttonStyle(.plain)
                } else {
                    FinanceCalendarEventRow(event: event, currency: currency)
                }
            }
        }.unifiedCard().accessibilityIdentifier("finance-calendar-day-events")
    }
}

struct FinanceCalendarEventRow: View {
    let event: FinanceCalendarEvent
    let currency: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: event.type == .income ? "arrow.down.left" : "arrow.up.right")
                .foregroundStyle(event.kind == .recorded ? ForgiaPalette.spending : ForgiaPalette.calendar)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title).font(.subheadline.weight(.medium))
                Text(event.kind == .recorded ? "Registrato" : event.kind == .recurrence
                    ? (event.date <= Date() ? "Ricorrenza da registrare · apri originale" : "Ricorrenza prevista · apri originale") : "Programmato")
                    .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
            }
            Spacer(minLength: 8)
            if let amount = event.amount {
                Text(amount, format: .currency(code: currency)).font(.subheadline.weight(.semibold)).monospacedDigit()
            } else { Image(systemName: "exclamationmark.triangle") }
        }.foregroundStyle(.primary).padding(.vertical, 6).accessibilityElement(children: .combine)
    }
}

struct FinanceCalendarPreview: View {
    let contoIDs: Set<UUID>
    let currency: String
    var initialDate = Date()
    var body: some View {
        NavigationLink {
            FinanceCalendarView(contoIDs: contoIDs, currency: currency, initialDate: initialDate)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                AnalysisPreviewHeading(title: "Calendario e timeline", icon: "calendar", tint: ForgiaPalette.calendar)
                Text("Consulta le spese nel calendario e le prossime scadenze nella timeline")
                    .font(.subheadline).foregroundStyle(ForgiaPalette.mutedText)
            }.unifiedCard(tint: ForgiaPalette.calendar).foregroundStyle(.primary)
        }.buttonStyle(.plain).financeCardEntrance().accessibilityIdentifier("finance-calendar-preview")
    }
}
