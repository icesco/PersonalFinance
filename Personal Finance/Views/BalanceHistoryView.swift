import SwiftUI
import SwiftData
import Charts
import FinanceCore
import CoreData

/// Gesture/selection updates redraw the plot without rebuilding its financial series.
private struct CachedBalanceSeriesContent<Content: View>: View {
    let contoIDs: Set<UUID>
    let interval: DateInterval
    @ViewBuilder let content: ([AccountBalanceSeries]) -> Content
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var phase
    @State private var reader = BalanceSeriesReader()
    @State private var series: [AccountBalanceSeries] = []
    @State private var loadedScope: Scope?
    @State private var revision = 0
    @State private var failed = false

    private struct Scope: Equatable {
        let ids: Set<UUID>
        let interval: DateInterval
    }
    private struct Request: Equatable {
        let scope: Scope
        let revision: Int
    }
    private var scope: Scope { Scope(ids: contoIDs, interval: interval) }

    var body: some View {
        Group {
            if loadedScope == scope {
                content(series)
            } else if failed {
                VStack(spacing: 8) {
                    Text("Grafico non disponibile").foregroundStyle(.secondary)
                    Button("Riprova") { revision &+= 1 }
                }.frame(maxWidth: .infinity)
            } else {
                ProgressView("Caricamento andamento…").frame(maxWidth: .infinity)
            }
        }
        .task(id: Request(scope: scope, revision: revision)) {
            let requestedScope = scope
            do {
                try await Task.sleep(for: .milliseconds(200))
                let value = try await reader.load(container: context.container, contoIDs: requestedScope.ids,
                                                  interval: requestedScope.interval)
                try Task.checkCancellation()
                var transaction = SwiftUI.Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    series = value
                    loadedScope = requestedScope
                    failed = false
                }
            } catch is CancellationError {
            } catch { failed = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: FinanceDataChangeCenter.notificationName).receive(on: RunLoop.main)) { notification in
            guard let change = FinanceDataChange.from(notification),
                  change.affects(container: context.container, contoIDs: contoIDs) else { return }
            revision &+= 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange).receive(on: RunLoop.main)) { _ in revision &+= 1 }
        .onReceive(NotificationCenter.default.publisher(for: .cloudSyncDidComplete).receive(on: RunLoop.main)) { _ in revision &+= 1 }
        .onChange(of: phase) { _, value in if value == .active { revision &+= 1 } }
        .task {
            do {
                while !Task.isCancelled {
                    try await Task.sleep(for: .seconds(60))
                    if phase == .active { revision &+= 1 }
                }
            } catch {}
        }
    }
}

struct BalanceHistoryView: View {
    @Query(sort: \Account.name) private var books: [Account]
    @State private var bookID: UUID?
    @State private var contoID: UUID?
    @State private var anchor = Date()
    @State private var yearly = false
    @State private var selectedDate: Date?

    init(bookID: UUID? = nil, contoID: UUID? = nil) {
        _bookID = State(initialValue: bookID)
        _contoID = State(initialValue: contoID)
    }
    private var book: Account? { books.first { $0.id == bookID } ?? books.first }
    private var conti: [Conto] { (book?.conti ?? []).sorted { ($0.name ?? "") < ($1.name ?? "") } }
    private var interval: DateInterval { Calendar.current.dateInterval(of: yearly ? .year : .month, for: anchor)! }
    private var currency: String { book?.currency ?? "EUR" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("Libro", selection: Binding(get: { book?.id }, set: { bookID = $0; contoID = nil; selectedDate = nil })) {
                    ForEach(books) { Text($0.name ?? "Libro").tag(Optional($0.id)) }
                }
                Picker("Conto", selection: $contoID) {
                    Text("Tutti i conti del libro").tag(nil as UUID?)
                    ForEach(conti) { Text($0.name ?? "Conto").tag(Optional($0.id)) }
                }
                Picker("Periodo", selection: $yearly) {
                    Text("Mese").tag(false)
                    Text("Anno").tag(true)
                }.pickerStyle(.segmented)
                HStack {
                    Button("Periodo precedente", systemImage: "chevron.left") { move(-1) }.labelStyle(.iconOnly)
                    Spacer()
                    Text(anchor, format: yearly ? .dateTime.year() : .dateTime.month(.wide).year())
                    Spacer()
                    Button("Periodo successivo", systemImage: "chevron.right") { move(1) }
                        .labelStyle(.iconOnly).disabled(interval.end > Date())
                }
                CachedBalanceSeriesContent(contoIDs: Set(conti.filter { contoID == nil || $0.id == contoID }.map(\.id)), interval: interval) { series in
                    BalanceHistoryChart(series: series, interval: interval, currency: currency, selectedDate: $selectedDate)
                        .unifiedCard(tint: ForgiaPalette.balance)
                }
                if let conto = conti.first(where: { $0.id == contoID }), conto.type == .savings {
                    SavingsAccountSummary(conto: conto)
                }
                Text("Saldo ricostruito dai saldi iniziali e dai movimenti datati fino a oggi. Il tratteggio indica la previsione basata sulle transazioni programmate e sulle ricorrenze fino alla fine del periodo. Sono compresi anche i conti archiviati del libro; le valute di libri diversi restano separate.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding()
        }
        .navigationTitle("Saldo storico")
        #if os(iOS)
        .toolbar(.visible, for: .navigationBar)
        #endif
        .onChange(of: contoID) { selectedDate = nil }
        .onChange(of: yearly) { selectedDate = nil }
    }
    private func move(_ value: Int) {
        anchor = Calendar.current.date(byAdding: yearly ? .year : .month, value: value, to: anchor) ?? anchor
        selectedDate = nil
    }

}


/// Uses the same account scope and date window as the surrounding analysis.
struct InlineBalanceHistoryDetailCard: View {
    let scopeContoIDs: Set<UUID>
    let interval: DateInterval
    let currency: String
    @State private var selectedDate: Date?

    var body: some View {
        CachedBalanceSeriesContent(contoIDs: scopeContoIDs, interval: interval) { series in
            VStack(alignment: .leading, spacing: 16) {
                Label("Saldo per conto", systemImage: "chart.xyaxis.line")
                    .font(.system(.title3, design: .serif, weight: .semibold))
                BalanceHistoryChart(series: series, interval: interval, currency: currency, selectedDate: $selectedDate)

            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .unifiedCard(tint: ForgiaPalette.balance)
            .accessibilityIdentifier("analysis-balance-history")
        }
        .onChange(of: interval) { selectedDate = nil }
        .onChange(of: scopeContoIDs) { selectedDate = nil }
    }
}


/// A compact entry point; the interactive chart keeps this exact scope in its detail.
struct InlineBalanceHistoryCard: View {
    let scopeContoIDs: Set<UUID>
    let interval: DateInterval
    let currency: String
    var periodTitle = ""

    var body: some View {
        CachedBalanceSeriesContent(contoIDs: scopeContoIDs, interval: interval) { series in
            NavigationLink {
                AnalysisDetailScreen(title: "Saldo per conto", periodTitle: periodTitle) {
                    InlineBalanceHistoryDetailCard(scopeContoIDs: scopeContoIDs, interval: interval, currency: currency)
                }
            } label: {
                VStack(alignment: .leading, spacing: 12) {
                    AnalysisPreviewHeading(title: "Saldo per conto", icon: "chart.xyaxis.line", tint: ForgiaPalette.balance)
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            if series.isEmpty {
                                Text("Nessun saldo nel periodo").font(.subheadline)
                            } else {
                                let total = series.reduce(Decimal.zero) { $0 + ($1.points.last?.balance ?? 0) }
                                Text(total, format: .currency(code: currency))
                                    .font(.system(.title2, design: .rounded, weight: .semibold)).monospacedDigit().financeNumericMotion(total).foregroundStyle(ForgiaPalette.balance)
                                Text(series.count == 1 ? "Saldo registrato · un conto" : "Saldo registrato · \(series.count) conti")
                                    .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        if !series.isEmpty {
                            BalanceHistoryMiniChart(series: series).frame(width: 100, height: 64).financeChartReveal()
                                .accessibilityHidden(true)
                        }
                    }
                }.unifiedCard(tint: ForgiaPalette.balance).foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .financeCardEntrance()
            .accessibilityIdentifier("analysis-balance-preview")
        }
    }
}

private struct BalanceHistoryMiniChart: View {
    let series: [AccountBalanceSeries]
    var body: some View {
        Chart {
            ForEach(series) { account in
                ForEach(account.points, id: \.date) { point in
                    LineMark(x: .value("Data", point.date),
                             y: .value("Saldo", NSDecimalNumber(decimal: point.balance).doubleValue),
                             series: .value("Conto", account.id.uuidString))
                        .foregroundStyle(account.color).interpolationMethod(.stepEnd)
                }
            }
        }
        .chartXAxis(.hidden).chartYAxis(.hidden).chartLegend(.hidden)
    }
}

/// Recorded balances, savings estimates, and scheduled projections remain separate.
private struct BalanceHistoryChart: View {
    let series: [AccountBalanceSeries]
    let interval: DateInterval
    let currency: String
    @Binding var selectedDate: Date?

    var body: some View {
        if let openingDate = series.first?.points.first?.date,
           let closingDate = series.first?.points.last?.date {
            let hasProjection = series.contains { !$0.projected.isEmpty }
            let endDate = hasProjection ? interval.end : closingDate
            let probeDate = selectedDate.map { min(max($0, openingDate), endDate) } ?? closingDate
            let isProjectedSelection = probeDate > closingDate
            let total = series.reduce(Decimal(0)) { $0 + $1.balance(at: probeDate) }
            let delta = series.reduce(Decimal(0)) { $0 + $1.balance(at: closingDate) - $1.balance(at: openingDate) }
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(isProjectedSelection
                         ? (series.count > 1 ? "Saldo totale previsto" : "Saldo previsto")
                         : (series.count > 1 ? "Saldo totale registrato" : "Saldo registrato"))
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Text(total, format: .currency(code: currency))
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .monospacedDigit().foregroundStyle(ForgiaPalette.balance)
                        .minimumScaleFactor(0.65).lineLimit(1)
                    Text(probeDate, format: .dateTime.day().month().year())
                        .font(.caption).foregroundStyle(.secondary)
                }.accessibilityElement(children: .combine)
                Label {
                    Text("\(delta >= 0 ? "+" : "")\(delta.formatted(.currency(code: currency))) nel periodo registrato")
                } icon: {
                    Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(delta >= 0 ? ForgiaPalette.balance : ForgiaPalette.deficit)

                BalanceHistoryPlot(series: series, interval: interval, currency: currency, selectedDate: $selectedDate)
                    .frame(height: 230).financeChartReveal()

                let hasSavings = series.contains(where: { $0.savingsCapital != nil })
                if hasProjection || hasSavings {
                    BalanceLineLegend(hasProjection: hasProjection, hasSavings: hasSavings,
                                      tint: series.count == 1 ? series[0].color : .secondary)
                }
                if hasSavings {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(series.filter { $0.savingsCapital != nil }) { account in
                            if let capital = account.savingsAmount(at: probeDate, estimated: false),
                               let value = account.savingsAmount(at: probeDate, estimated: true) {
                                Text("\(account.name): versato \(capital.formatted(.currency(code: currency))) · controvalore \(value.formatted(.currency(code: currency)))")
                            }
                        }
                    }.font(.caption).foregroundStyle(.secondary)
                }
                if hasProjection {
                    let projectedTotal = series.reduce(Decimal(0)) { $0 + $1.balance(at: endDate) }
                    Text("Previsto a fine periodo: \(projectedTotal.formatted(.currency(code: currency)))")
                        .font(.caption.weight(.semibold))
                }
                VStack(spacing: 10) {
                    ForEach(series) { account in
                        HStack(spacing: 8) {
                            Capsule().fill(account.color).frame(width: 18, height: 3)
                                .accessibilityHidden(true)
                            Text(account.name).font(.caption.weight(.medium))
                            Spacer(minLength: 8)
                            Text(account.balance(at: probeDate), format: .currency(code: currency))
                                .font(.caption.weight(.semibold)).monospacedDigit()
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                Text(hasProjection
                     ? "Il tratteggio considera solo transazioni programmate e ricorrenze. Le spese e le entrate non programmate possono cambiare il saldo. Seleziona una data per leggere i saldi."
                     : "Seleziona un punto del grafico per leggere il saldo di ogni conto. Solo movimenti registrati.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } else {
            ContentUnavailableView("Nessun saldo nel periodo", systemImage: "chart.xyaxis.line")
        }
    }


}

private struct BalanceLineLegend: View {
    let hasProjection: Bool
    let hasSavings: Bool
    let tint: Color
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
            GridRow {
                BalanceLegendItem(title: "Saldo registrato", tint: tint, dash: [], opacity: 1)
                if hasProjection {
                    BalanceLegendItem(title: "Saldo previsto", tint: tint, dash: [5, 4], opacity: 0.65)
                }
            }
            if hasSavings {
                GridRow {
                    BalanceLegendItem(title: "Capitale versato", tint: tint, dash: [], opacity: 0.45)
                    BalanceLegendItem(title: "Controvalore stimato", tint: tint, dash: [2, 3], opacity: 1)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BalanceLegendItem: View {
    let title: LocalizedStringKey
    let tint: Color
    let dash: [CGFloat]
    let opacity: Double
    var body: some View {
        HStack(spacing: 7) {
            LegendLine().stroke(tint.opacity(opacity), style: StrokeStyle(lineWidth: 2, dash: dash))
                .frame(width: 25, height: 12).accessibilityHidden(true)
            Text(title).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.accessibilityElement(children: .combine)
    }
    private struct LegendLine: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: 0, y: rect.midY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            }
        }
    }
}

#if DEBUG
/// Isolated visual verification data; never written to the user's ledger.
struct BalanceHistoryFixture: View {
    fileprivate static let data: (container: ModelContainer, ids: Set<UUID>, interval: DateInterval) = {
        let container = try! FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let book = Account(name: "Demo", currency: "EUR")
        let current = Conto(name: "Conto corrente", type: .checking, initialBalance: 3600, color: AccountPalette.ottanio)
        let savings = Conto(name: "Risparmi", type: .savings, initialBalance: 7000, color: AccountPalette.petrolio)
        let cash = Conto(name: "Contanti", type: .cash, initialBalance: 300, color: AccountPalette.ocra)
        book.conti = [current, savings, cash]
        for conto in book.conti! { conto.account = book }
        container.mainContext.insert(book)
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -30, to: now)!
        if ProcessInfo.processInfo.arguments.contains("UITEST_SAVINGS") {
            try! savings.setSavingsRate(ProcessInfo.processInfo.arguments.contains("UITEST_SAVINGS_LOSS") ? -3 : 3, effectiveDate: Calendar.current.date(byAdding: .year, value: -1, to: start)!)
            try! savings.setSavingsRate(ProcessInfo.processInfo.arguments.contains("UITEST_SAVINGS_LOSS") ? -4 : 4, effectiveDate: start)
            try! SavingsAccountEdits.linkGoal(conto: savings, existingID: nil, target: 10000, context: container.mainContext)
        }
        @MainActor func add(_ day: Int, _ amount: Decimal, _ type: TransactionType, from: Conto? = nil, to: Conto? = nil) {
            let transaction = FinanceCore.Transaction(amount: amount, type: type,
                date: Calendar.current.date(byAdding: .day, value: day, to: start)!)
            if let from { transaction.setFromConto(from) }
            if let to { transaction.setToConto(to) }
            container.mainContext.insert(transaction)
        }
        add(3, 250, .expense, from: current)
        add(7, 80, .expense, from: cash)
        add(11, 1800, .income, to: current)
        add(15, 600, .transfer, from: current, to: savings)
        add(19, 450, .expense, from: current)
        add(23, 100, .transfer, from: current, to: cash)
        add(27, 150, .expense, from: current)
        add(33, 700, .transfer, from: current, to: savings)
        add(38, 1800, .income, to: current)
        add(45, 800, .expense, from: current)
        try! container.mainContext.save()
        return (container, Set(book.conti!.map(\.id)), DateInterval(start: start, end: Calendar.current.dateInterval(of: .month, for: now)!.end))
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Registrato e previsto · dati demo")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if ProcessInfo.processInfo.arguments.contains("UITEST_SAVINGS"),
                       let savings = (try? Self.data.container.mainContext.fetch(FetchDescriptor<Conto>()))?.first(where: { $0.type == .savings }) {
                        InlineBalanceHistoryDetailCard(scopeContoIDs: [savings.id], interval: Self.data.interval, currency: "EUR")
                        SavingsAccountSummary(conto: savings)
                            .unifiedCard(tint: ForgiaPalette.balance)
                    } else {
                        InlineBalanceHistoryDetailCard(scopeContoIDs: Self.data.ids, interval: Self.data.interval, currency: "EUR")
                    }
                }.padding()
            }
            .themedBackground()
            .navigationTitle("Analisi")
        }
        .modelContainer(Self.data.container)
    }
}
#endif

#if DEBUG
struct BalanceWidgetVisualFixture: View {
    private static let history: WidgetBalanceSnapshot = {
        let context = BalanceHistoryFixture.data.container.mainContext
        return WidgetBalanceSnapshot.make(period: .month, conti: try! context.fetch(FetchDescriptor<Conto>()),
            transactions: try! context.fetch(FetchDescriptor<FinanceCore.Transaction>()),
            resolutions: [], now: Date())
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Anteprima con dati demo").font(.caption).foregroundStyle(.secondary)
                    if ProcessInfo.processInfo.arguments.contains("UITEST_BALANCE_WIDGET_PORTRAIT") {
                        Text("Extra large verticale · iPhone").font(.caption.weight(.semibold))
                        FinanceBalanceWidgetContent(history: Self.history, bookName: "Demo", currency: "EUR", size: .extraLargePortrait)
                            .padding(16).frame(height: 550)
                            .background(.background, in: RoundedRectangle(cornerRadius: 22))
                    } else {
                        if !ProcessInfo.processInfo.arguments.contains("UITEST_BALANCE_WIDGET_XL") {
                            Text("Piccolo").font(.caption.weight(.semibold))
                            FinanceBalanceWidgetContent(history: Self.history, bookName: "Demo", currency: "EUR", size: .small)
                                .padding(16).frame(width: 170, height: 170)
                                .background(.background, in: RoundedRectangle(cornerRadius: 22))
                            Text("Medio").font(.caption.weight(.semibold))
                            FinanceBalanceWidgetContent(history: Self.history, bookName: "Demo", currency: "EUR", size: .medium)
                                .padding(16).frame(height: 170)
                                .background(.background, in: RoundedRectangle(cornerRadius: 22))
                            Text("Grande").font(.caption.weight(.semibold))
                            FinanceBalanceWidgetContent(history: Self.history, bookName: "Demo", currency: "EUR")
                                .padding(16).frame(height: 340)
                                .background(.background, in: RoundedRectangle(cornerRadius: 22))
                        }
                        Text("Extra large · iPad").font(.caption.weight(.semibold))
                        ScrollView(.horizontal) {
                            FinanceBalanceWidgetContent(history: Self.history, bookName: "Demo", currency: "EUR", size: .extraLarge)
                                .padding(20).frame(width: 720, height: 340)
                                .background(.background, in: RoundedRectangle(cornerRadius: 22))
                        }
                    }
                }.padding()
            }.themedBackground().navigationTitle("Widget saldo")
        }
    }
}
#endif
