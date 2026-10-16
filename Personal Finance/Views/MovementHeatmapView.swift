import SwiftUI
import SwiftData
import FinanceCore

private var movementHeatmapLocale: Locale {
    Locale(identifier: Locale.preferredLanguages.first ?? Locale.current.identifier)
}

private extension MovementHeatmapMode {
    var title: LocalizedStringKey {
        switch self {
        case .expense: "Uscite"
        case .income: "Entrate"
        case .net: "Netto"
        }
    }

    func tint(for totals: MovementHeatmapTotals) -> Color {
        let value = value(in: totals) ?? 0
        switch self {
        case .expense: return value < 0 ? AnalysisPalette.margin : AnalysisPalette.spending
        case .income, .net: return value < 0 ? AnalysisPalette.spending : AnalysisPalette.margin
        }
    }
}

private struct MovementHeatmapData<Content: View>: View {
    let contoIDs: Set<UUID>
    let currency: String
    let month: Date
    var compact = false
    @ViewBuilder let content: (MovementHeatmapMonth) -> Content
    @Environment(\.modelContext) private var context
    @State private var reader = MovementHeatmapReader()
    @State private var snapshot: MovementHeatmapMonth?
    @State private var loadedScope: PlanningSnapshotScope?
    @State private var loadedCurrency: String?
    @State private var revision = 0
    @State private var failed = false

    private var scope: PlanningSnapshotScope { .init(container: context.container, ids: contoIDs, month: month) }
    private struct Request: Equatable {
        let planning: PlanningSnapshotRequest
        let currency: String
    }
    private var request: Request { .init(planning: .init(scope: scope, revision: revision), currency: currency) }

    var body: some View {
        Group {
            if failed {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Mappa non disponibile").foregroundStyle(ForgiaPalette.mutedText)
                    if !compact { Button("Riprova") { revision &+= 1 } }
                }
            } else if loadedScope == scope, loadedCurrency == currency, let snapshot {
                content(snapshot)
            } else {
                FormiLoadingView("Caricamento movimenti…").frame(maxWidth: .infinity)
            }
        }
        .modifier(PlanningSnapshotRefresh(contoIDs: contoIDs, revision: $revision))
        .task(id: request) {
            let requested = request
            failed = false
            do {
                let value: MovementHeatmapMonth
                if context.hasChanges {
                    value = try MovementHeatmapReader.read(in: context, contoIDs: contoIDs, currency: currency, month: month)
                } else {
                    value = try await reader.load(container: context.container, contoIDs: contoIDs, currency: currency, month: month)
                }
                try Task.checkCancellation()
                guard request == requested else { return }
                snapshot = value; loadedScope = requested.planning.scope; loadedCurrency = requested.currency
            } catch is CancellationError {
            } catch {
                guard request == requested, !Task.isCancelled else { return }
                failed = true
            }
        }
    }
}

struct MovementHeatmapPreview: View {
    let contoIDs: Set<UUID>
    let currency: String
    var initialDate = Date()

    var body: some View {
        NavigationLink {
            MovementHeatmapView(contoIDs: contoIDs, currency: currency, initialDate: initialDate)
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                AnalysisPreviewHeading(title: "Mappa dei movimenti", icon: "calendar", tint: AnalysisPalette.spending)
                HStack {
                    Text(initialDate, format: .dateTime.month(.wide).year().locale(movementHeatmapLocale))
                    Spacer()
                    Text("Uscite registrate")
                }.font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                MovementHeatmapData(contoIDs: contoIDs, currency: currency, month: initialDate, compact: true) { snapshot in
                    MovementHeatmapGrid(snapshot: snapshot, mode: .expense, currency: currency, compact: true)
                        .accessibilityIdentifier("heatmap-preview-calendar")
                }
                Text("Entrate e uscite, giorno per giorno")
                    .font(.subheadline).foregroundStyle(ForgiaPalette.accent)
            }.unifiedCard(tint: AnalysisPalette.spending)
        }
        .buttonStyle(.plain)
        .financeCardEntrance()
        .accessibilityIdentifier("analysis-heatmap-preview")
    }
}

struct MovementHeatmapView: View {
    let contoIDs: Set<UUID>
    let currency: String
    @Query private var conti: [Conto]
    @State private var selectedContoID: UUID?
    @State private var month: Date
    @State private var selectedDate: Date
    @State private var mode: MovementHeatmapMode = .expense

    init(contoIDs: Set<UUID>, currency: String, initialDate: Date = Date()) {
        self.contoIDs = contoIDs; self.currency = currency
        let ids = Array(contoIDs)
        _conti = Query(filter: #Predicate<Conto> { ids.contains($0.id) }, sort: \Conto.name)
        let calendar = Calendar.current
        let initial = min(initialDate, Date())
        _month = State(initialValue: calendar.dateInterval(of: .month, for: initial)!.start)
        _selectedDate = State(initialValue: calendar.startOfDay(for: initial))
    }

    private var availableConti: [Conto] { conti.filter { ($0.account?.currency ?? "EUR") == currency } }
    private var selectedIDs: Set<UUID> {
        let ids = Set(availableConti.map(\.id))
        guard let selectedContoID else { return ids }
        return ids.contains(selectedContoID) ? [selectedContoID] : []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("Conti inclusi", selection: $selectedContoID) {
                    Text("Tutti i conti inclusi").tag(nil as UUID?)
                    ForEach(availableConti) { conto in
                        Text(conto.isActive == false ? "\(conto.name ?? "Conto") (archiviato)" : conto.name ?? "Conto")
                            .tag(Optional(conto.id))
                    }
                    if let selectedContoID, !availableConti.contains(where: { $0.id == selectedContoID }) {
                        Text("Conto non disponibile").tag(Optional(selectedContoID))
                    }
                }
                .pickerStyle(.menu).controlSize(.large).frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .accessibilityIdentifier("heatmap-account-picker")
                if availableConti.count != conti.count {
                    Text("Sono mostrati solo i conti in \(currency). Le altre valute restano separate.")
                        .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                }

                monthHeader
                MovementHeatmapData(contoIDs: selectedIDs, currency: currency, month: month) { snapshot in
                    MovementHeatmapContent(snapshot: snapshot, selectedDate: $selectedDate, currency: currency, mode: $mode)
                }
                DisclosureGroup("Come leggere la mappa") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Il colore indica l’importo giornaliero. La scala resta identica quando cambi conto.")
                        Text("Il netto è la differenza tra entrate e uscite, non il saldo disponibile. I trasferimenti sono visibili nel dettaglio del giorno ma esclusi dai totali.")
                        Text("Solo movimenti registrati fino a oggi. I conti restano nell’ambito selezionato in Analisi e nella valuta indicata; non vengono applicate conversioni implicite.")
                    }.font(.footnote).foregroundStyle(ForgiaPalette.mutedText).padding(.top, 8)
                }.tint(ForgiaPalette.accent)
            }.frame(maxWidth: 760).frame(maxWidth: .infinity).padding(20)
        }
        .themedBackground(tint: .clear)
        .environment(\.financeCardSurfaceStyle, .themed)
        .navigationTitle("Mappa dei movimenti")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        #endif
    }

    private var monthHeader: some View {
        HStack {
            Button { moveMonth(-1) } label: {
                Image(systemName: "chevron.left").frame(width: 48, height: 48).contentShape(Rectangle())
            }.accessibilityLabel("Mese precedente")
                .accessibilityIdentifier("heatmap-previous-month")
            Spacer(minLength: 0)
            Text(month, format: .dateTime.month(.wide).year().locale(movementHeatmapLocale))
                .font(.system(.headline, design: .serif, weight: .semibold))
                .foregroundStyle(ForgiaPalette.accent)
                .accessibilityIdentifier("heatmap-month")
            Spacer(minLength: 0)
            Button { moveMonth(1) } label: {
                Image(systemName: "chevron.right").frame(width: 48, height: 48).contentShape(Rectangle())
            }.accessibilityLabel("Mese successivo")
                .disabled(Calendar.current.dateInterval(of: .month, for: month)!.end > Date())
                .accessibilityIdentifier("heatmap-next-month")
        }.buttonStyle(.plain)
    }

    private func moveMonth(_ offset: Int) {
        let calendar = Calendar.current
        guard let next = calendar.date(byAdding: .month, value: offset, to: month) else { return }
        month = next
        selectedDate = calendar.isDate(next, equalTo: Date(), toGranularity: .month)
            ? calendar.startOfDay(for: Date()) : next
    }
}

private struct MovementHeatmapContent: View {
    let snapshot: MovementHeatmapMonth
    @Binding var selectedDate: Date
    let currency: String
    @Binding var mode: MovementHeatmapMode

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Picker("Misura", selection: $mode) {
                ForEach(MovementHeatmapMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).accessibilityIdentifier("heatmap-mode")
            VStack(alignment: .leading, spacing: 8) {
                Text(mode.title).font(.subheadline).foregroundStyle(ForgiaPalette.mutedText)
                if let amount = mode.value(in: snapshot.totals) {
                    Text(amount, format: .currency(code: currency))
                        .analysisMetric().foregroundStyle(mode.tint(for: snapshot.totals))
                        .accessibilityIdentifier("heatmap-total")
                } else {
                    Label("Importi da verificare", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(ForgiaPalette.mutedText)
                }
                Text("Registrato fino al \(min(snapshot.generatedAt, snapshot.interval.end.addingTimeInterval(-1)), format: .dateTime.day().month(.wide).locale(movementHeatmapLocale))")
                    .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
            }
            VStack(alignment: .leading, spacing: 16) {
                MovementHeatmapGrid(snapshot: snapshot, mode: mode, currency: currency, selectedDate: selectedDate) { selectedDate = $0 }
                MovementHeatmapLegend(mode: mode, currency: currency)
            }.unifiedCard(tint: AnalysisPalette.spending)
            if snapshot.isEmpty {
                Text("Nessun movimento registrato nel mese per i conti selezionati.")
                    .font(.subheadline).foregroundStyle(ForgiaPalette.mutedText)
                    .accessibilityIdentifier("heatmap-empty-month")
            }
            if let day = snapshot.days.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }) {
                MovementHeatmapDayDetail(day: day, currency: currency)
            }
        }
    }
}

private struct MovementHeatmapGrid: View {
    let snapshot: MovementHeatmapMonth
    let mode: MovementHeatmapMode
    let currency: String
    var compact = false
    var selectedDate: Date?
    var select: ((Date) -> Void)?
    @Environment(\.calendar) private var calendar

    private var leadingDates: [Date] {
        let offset = (calendar.component(.weekday, from: snapshot.interval.start) - calendar.firstWeekday + 7) % 7
        return (0..<offset).compactMap { calendar.date(byAdding: .day, value: $0 - offset, to: snapshot.interval.start) }
    }
    private var weekdays: [Int] { (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 } }
    private var weekdaySymbols: [String] {
        var value = calendar
        value.locale = movementHeatmapLocale
        return value.veryShortStandaloneWeekdaySymbols
    }

    var body: some View {
        VStack(spacing: compact ? 5 : 8) {
            HStack(spacing: compact ? 5 : 6) {
                ForEach(weekdays, id: \.self) { weekday in
                    Text(weekdaySymbols[weekday])
                        .font(compact ? .caption2 : .caption).foregroundStyle(ForgiaPalette.mutedText)
                        .frame(maxWidth: .infinity)
                }
            }.accessibilityHidden(true)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: compact ? 5 : 6), count: 7), spacing: compact ? 5 : 6) {
                ForEach(leadingDates, id: \.self) { _ in Color.clear.frame(height: compact ? 24 : 52).accessibilityHidden(true) }
                ForEach(snapshot.days) { day in
                    if let select, !compact {
                        Button { select(day.date) } label: { cell(day) }
                            .buttonStyle(.plain).disabled(day.isFuture)
                            .accessibilityLabel(dayLabel(day))
                            .accessibilityAddTraits(selectedDate == day.date ? .isSelected : [])
                            .accessibilityIdentifier("heatmap-day-\(calendar.component(.day, from: day.date))")
                    } else {
                        cell(day).accessibilityHidden(true)
                    }
                }
            }
        }
        .accessibilityElement(children: compact ? .ignore : .contain)
        .accessibilityLabel(compact ? "Anteprima del calendario delle uscite registrate" : "Calendario dei movimenti")
    }

    private func cell(_ day: MovementHeatmapDay) -> some View {
        let level = mode.level(in: day.totals)
        let opacity = level == 0 ? 0.07 : 0.1 + Double(level) * 0.08
        return VStack(spacing: 1) {
            Text(day.date, format: .dateTime.day())
                .font(compact ? .caption2 : .subheadline.weight(.medium)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.8)
            if !compact { Text(marker(day)).font(.caption2).frame(height: 12) }
        }
        .foregroundStyle(day.isFuture ? ForgiaPalette.mutedText.opacity(0.45) : .primary)
        .frame(maxWidth: .infinity, minHeight: compact ? 24 : 52)
        .background(mode.tint(for: day.totals).opacity(day.isFuture ? 0.03 : opacity), in: RoundedRectangle(cornerRadius: compact ? 5 : 10))
        .overlay {
            if selectedDate == day.date, !compact {
                RoundedRectangle(cornerRadius: 10).strokeBorder(ForgiaPalette.accent, lineWidth: 2)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }

    private func marker(_ day: MovementHeatmapDay) -> String {
        if day.isFuture { return "" }
        if day.isEmpty { return "·" }
        if day.onlyTransfers { return "⇄" }
        guard let value = mode.value(in: day.totals) else { return "!" }
        if day.hasBalancedActivity { return "±" }
        return mode == .net ? (value > 0 ? "+" : value < 0 ? "−" : "·") : ""
    }

    private func dayLabel(_ day: MovementHeatmapDay) -> String {
        let date = day.date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(movementHeatmapLocale))
        if day.isFuture { return "\(date), \(String(localized: "Giorno futuro"))" }
        if day.isEmpty { return "\(date), \(String(localized: "Nessun movimento"))" }
        if day.onlyTransfers { return "\(date), \(String(localized: "Solo trasferimenti, esclusi dai totali"))" }
        guard let amount = mode.value(in: day.totals) else { return "\(date), \(String(localized: "Importi da verificare"))" }
        let title = String(localized: mode == .expense ? "Uscite" : mode == .income ? "Entrate" : "Netto")
        return "\(date), \(title), \(amount.formatted(.currency(code: currency)))"
    }
}

private struct MovementHeatmapLegend: View {
    let mode: MovementHeatmapMode
    let currency: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Intensità giornaliera · \(currency)").font(.caption).foregroundStyle(ForgiaPalette.mutedText)
            HStack(spacing: 10) {
                ForEach([25, 100, 500, 501], id: \.self) { ceiling in
                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill((mode == .income ? AnalysisPalette.margin : AnalysisPalette.spending)
                                .opacity(ceiling == 25 ? 0.18 : ceiling == 100 ? 0.26 : ceiling == 500 ? 0.34 : 0.42))
                            .frame(height: 7)
                        Text(ceiling == 501 ? ">500" : "≤\(ceiling)")
                            .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if mode == .net {
                Text("+ Entrate prevalenti · − Uscite prevalenti")
                    .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
            }
            Text("· Nessun movimento   ⇄ Solo trasferimenti   ± Entrate = uscite")
                .font(.caption).foregroundStyle(ForgiaPalette.mutedText).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct MovementHeatmapDayDetail: View {
    let day: MovementHeatmapDay
    let currency: String
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(day.date, format: .dateTime.weekday(.wide).day().month(.wide).locale(movementHeatmapLocale))
                .font(.system(.title3, design: .serif, weight: .semibold))
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) { totals }
                VStack(alignment: .leading, spacing: 12) { totals }
            }
            if day.isEmpty {
                Text("Nessun movimento registrato in questo giorno per i conti selezionati.")
                    .font(.subheadline).foregroundStyle(ForgiaPalette.mutedText)
            } else {
                HeatmapDayTransactions(entries: day.entries) { transactions in
                    ForEach(day.entries) { entry in
                        if let transaction = transactions[entry.id] {
                            NavigationLink { TransactionDetailView(transaction: transaction) } label: {
                                MovementHeatmapEntryRow(entry: entry, currency: currency)
                            }.buttonStyle(.plain)
                                .accessibilityIdentifier("heatmap-entry-\(entry.id)")
                        } else {
                            MovementHeatmapEntryRow(entry: entry, currency: currency)
                        }
                    }
                }
            }
        }.unifiedCard()
    }

    @ViewBuilder private var totals: some View {
        amount("Entrate", day.totals.income)
        amount("Uscite", day.totals.expenses)
        amount("Netto", day.totals.net)
    }

    private func amount(_ title: LocalizedStringKey, _ value: Decimal?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(ForgiaPalette.mutedText)
            if let value { Text(value, format: .currency(code: currency)).font(.subheadline.weight(.semibold)).monospacedDigit().fixedSize() }
            else { Text("Da verificare").font(.subheadline) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HeatmapDayTransactions<Content: View>: View {
    @Query private var transactions: [FinanceCore.Transaction]
    @ViewBuilder let content: ([UUID: FinanceCore.Transaction]) -> Content
    init(entries: [MovementHeatmapEntry], @ViewBuilder content: @escaping ([UUID: FinanceCore.Transaction]) -> Content) {
        let ids = entries.map(\.id)
        _transactions = Query(filter: #Predicate<FinanceCore.Transaction> { ids.contains($0.id) })
        self.content = content
    }
    var body: some View { content(Dictionary(transactions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })) }
}

private struct MovementHeatmapEntryRow: View {
    let entry: MovementHeatmapEntry
    let currency: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: entry.type.icon).foregroundStyle(ForgiaPalette.accent).frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title ?? String(localized: "Movimento"))
                    .font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                if entry.type == .transfer {
                    Text("\(entry.accountName ?? String(localized: "Altro conto")) → \(entry.destinationName ?? String(localized: "Altro conto"))")
                    Text("Trasferimento escluso dai totali")
                } else if let name = entry.accountName { Text(name) }
            }.font(.caption).foregroundStyle(ForgiaPalette.mutedText).frame(maxWidth: .infinity, alignment: .leading)
            if let amount = entry.amount {
                Text(entry.type == .expense ? -amount : amount, format: .currency(code: currency))
                    .font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(.primary)
                    .fixedSize(horizontal: true, vertical: false)
            } else { Image(systemName: "exclamationmark.triangle").accessibilityLabel("Importo da verificare") }
        }.padding(.vertical, 8).frame(minHeight: 48).contentShape(Rectangle()).accessibilityElement(children: .combine)
    }
}
