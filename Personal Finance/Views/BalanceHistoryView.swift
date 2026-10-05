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
        let selected = selectedDate.flatMap { date in history.last { $0.date <= date } } ?? history.last
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
                if let selected {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selected.balance, format: .currency(code: currency)).font(.largeTitle.bold()).monospacedDigit()
                        Text(selectedDate ?? selected.date, format: .dateTime.day().month().year()).foregroundStyle(.secondary)
                    }.accessibilityElement(children: .combine)
                    Chart {
                        ForEach(history, id: \.date) { point in
                            LineMark(x: .value("Data", point.date), y: .value("Saldo", NSDecimalNumber(decimal: point.balance).doubleValue))
                                .interpolationMethod(.stepEnd)
                        }
                        if let selectedDate {
                            RuleMark(x: .value("Data selezionata", selectedDate)).foregroundStyle(.secondary)
                        }
                    }
                    .chartXSelection(value: $selectedDate)
                    .chartYScale(domain: yDomain(history))
                    .frame(height: 250)
                    .accessibilityLabel("Andamento del saldo registrato")
                    Text("Tocca o trascina sul grafico per leggere data e saldo.").font(.caption).foregroundStyle(.secondary)
                } else {
                    ContentUnavailableView("Nessun conto nel periodo", systemImage: "chart.xyaxis.line")
                }
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
