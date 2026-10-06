import SwiftUI
import SwiftData
import Charts
import FinanceCore

struct BalanceHistoryView: View {
    @Query(sort: \Account.name) private var books: [Account]
    @Query private var transactions: [FinanceCore.Transaction]
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
    private var points: [BalanceDataPoint] {
        let selected = conti.filter { contoID == nil || $0.id == contoID }
        let snapshots = transactions.map {
            TransactionSnapshot(id: $0.id, amount: $0.amount ?? 0, type: $0.type, date: $0.date,
                                fromContoId: $0.fromContoId ?? $0.fromConto?.id,
                                toContoId: $0.toContoId ?? $0.toConto?.id, destinationAmount: $0.destinationAmount)
        }
        return RecordedBalanceHistory.points(transactions: snapshots, contiIDs: Set(selected.map(\.id)),
                                             initialBalance: selected.reduce(0) { $0 + ($1.initialBalance ?? 0) },
                                             interval: interval, now: Date())
    }

    var body: some View {
        let history = points
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
                BalanceHistoryChart(points: history, currency: currency, selectedDate: $selectedDate)
                    .unifiedCard()
                Text("Saldo ricostruito dai saldi iniziali e dai movimenti datati fino a oggi. Le ricorrenze future e le proiezioni non sono incluse. Sono compresi anche i conti archiviati del libro; le valute di libri diversi restano separate.")
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
    private func yDomain(_ points: [BalanceDataPoint]) -> ClosedRange<Double> {
        let domain = BalanceCalculator.chartYDomain(dataPoints: points)
        return NSDecimalNumber(decimal: domain.lowerBound).doubleValue...NSDecimalNumber(decimal: domain.upperBound).doubleValue
    }
}


/// Uses the same account scope and date window as the surrounding analysis.
struct InlineBalanceHistoryCard: View {
    let scopeContoIDs: Set<UUID>
    let interval: DateInterval
    let currency: String
    @Query private var conti: [Conto]
    @Query private var transactions: [FinanceCore.Transaction]
    @State private var selectedDate: Date?

    private var history: [BalanceDataPoint] {
        let selected = conti.filter { scopeContoIDs.contains($0.id) }
        guard !selected.isEmpty else { return [] }
        let snapshots = transactions.map {
            TransactionSnapshot(id: $0.id, amount: $0.amount ?? 0, type: $0.type, date: $0.date,
                                fromContoId: $0.fromContoId ?? $0.fromConto?.id,
                                toContoId: $0.toContoId ?? $0.toConto?.id, destinationAmount: $0.destinationAmount)
        }
        return RecordedBalanceHistory.points(transactions: snapshots, contiIDs: scopeContoIDs,
            initialBalance: selected.reduce(0) { $0 + ($1.initialBalance ?? 0) }, interval: interval, now: Date())
    }

    var body: some View {
        let points = history
        VStack(alignment: .leading, spacing: 16) {
            Label("Saldo nel periodo", systemImage: "chart.xyaxis.line")
                .font(.system(.title3, design: .serif, weight: .semibold))
            BalanceHistoryChart(points: points, currency: currency, selectedDate: $selectedDate)

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .unifiedCard()
        .accessibilityIdentifier("analysis-balance-history")
        .onChange(of: interval) { selectedDate = nil }
        .onChange(of: scopeContoIDs) { selectedDate = nil }
    }
}


/// Shared presentation: ledger values stay stepped rather than inventing intermediate balances.
private struct BalanceHistoryChart: View {
    let points: [BalanceDataPoint]
    let currency: String
    @Binding var selectedDate: Date?
    private let balanceColor = Color(hex: "#238B83")
    private let openingColor = Color(hex: "#9575CD")

    var body: some View {
        if let opening = points.first, let closing = points.last {
            let probeDate = selectedDate.map { min(max($0, opening.date), closing.date) }
            let selected = probeDate.flatMap { date in points.last { $0.date <= date } } ?? closing
            let delta = closing.balance - opening.balance
            let domain = BalanceCalculator.chartYDomain(dataPoints: points)
            let lower = NSDecimalNumber(decimal: domain.lowerBound).doubleValue
            let upper = NSDecimalNumber(decimal: domain.upperBound).doubleValue
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(selectedDate == nil ? "Saldo finale registrato" : "Saldo selezionato")
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Text(selected.balance, format: .currency(code: currency))
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .monospacedDigit().foregroundStyle(balanceColor)
                        .minimumScaleFactor(0.65).lineLimit(1)
                    Text(probeDate ?? selected.date,
                         format: .dateTime.day().month().year())
                        .font(.caption).foregroundStyle(.secondary)
                }.accessibilityElement(children: .combine)
                Label {
                    Text("\(delta >= 0 ? "+" : "")\(delta.formatted(.currency(code: currency))) nel periodo")
                } icon: {
                    Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(delta >= 0 ? balanceColor : Color(hex: "#C06748"))
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background((delta >= 0 ? balanceColor : Color(hex: "#C06748")).opacity(0.1), in: Capsule())

                Chart {
                    ForEach(points, id: \.date) { point in
                        AreaMark(x: .value("Data", point.date), yStart: .value("Base", lower),
                                 yEnd: .value("Saldo", NSDecimalNumber(decimal: point.balance).doubleValue))
                            .interpolationMethod(.stepEnd)
                            .foregroundStyle(LinearGradient(colors: [balanceColor.opacity(0.28), balanceColor.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("Data", point.date), y: .value("Saldo", NSDecimalNumber(decimal: point.balance).doubleValue))
                            .interpolationMethod(.stepEnd)
                            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                            .foregroundStyle(balanceColor)
                    }
                    RuleMark(y: .value("Saldo iniziale", NSDecimalNumber(decimal: opening.balance).doubleValue))
                        .foregroundStyle(openingColor.opacity(0.8))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    if let selectedDate {
                        RuleMark(x: .value("Selezione", min(max(selectedDate, opening.date), closing.date)))
                            .foregroundStyle(balanceColor.opacity(0.35))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                    PointMark(x: .value("Data", probeDate ?? closing.date),
                              y: .value("Saldo", NSDecimalNumber(decimal: selected.balance).doubleValue))
                        .foregroundStyle(balanceColor).symbolSize(65)
                }
                .chartYScale(domain: lower...upper)
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4])).foregroundStyle(.secondary.opacity(0.2))
                    AxisValueLabel { if let amount = value.as(Double.self) { Text(amount, format: .number.notation(.compactName)).font(.caption2) } }
                } }
                .chartXSelection(value: $selectedDate)
                .frame(height: 230)
                .accessibilityLabel("Saldo registrato, con riferimento al saldo iniziale. Valori in \(currency).")
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 20) { legend }
                    VStack(alignment: .leading, spacing: 8) { legend }
                }
                .font(.caption)
                Text("Tocca o trascina per leggere il saldo. Solo movimenti registrati, senza proiezioni future.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } else {
            ContentUnavailableView("Nessun saldo nel periodo", systemImage: "chart.xyaxis.line")
        }
    }
    @ViewBuilder private var legend: some View {
        Label { Text("Saldo · \(currency)") } icon: { Capsule().fill(balanceColor).frame(width: 18, height: 4) }
        Label { Text("Inizio periodo") } icon: {
            HStack(spacing: 3) { Capsule().fill(openingColor).frame(width: 7, height: 3); Capsule().fill(openingColor).frame(width: 7, height: 3) }
        }
    }
}
