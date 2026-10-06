import SwiftUI
import Charts
import FinanceCore

/// A factual drill-down of recorded expenses, excluding transfers.
struct SpendingOverviewView: View {
    @Environment(\.locale) private var locale
    let transactions: [DirectionTransaction]
    let currency: String
    let scopeContoIDs: Set<UUID>
    var initialBookID: UUID? = nil

    @State private var period: SpendingAnalysisPeriod? = .month
    @State private var customStart = Calendar.current.dateInterval(of: .month, for: Date())!.start
    @State private var customEnd = Date()
    @State private var showingCustomPeriod = false
    @State private var anchor = Date()

    private var window: SpendingAnalysisWindow {
        if let period { return SpendingAnalysisWindow(period: period, anchor: anchor) }
        return SpendingAnalysisWindow(start: customStart, endInclusive: customEnd)!

    }
    private var interval: DateInterval { window.interval }
    private var comparisonInterval: DateInterval { window.previous }
    private var report: RecordedSpendingReport {
        RecordedSpendingReport.calculate(transactions: transactions, interval: interval, previous: comparisonInterval)
    }

    private var largestAmount: Decimal {
        report.categories.first?.amount ?? 0
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Dove spendi")
                        .font(.system(size: 36, weight: .semibold, design: .serif))
                        .tracking(-0.8)
                    Text("Le tue uscite registrate")
                        .font(.subheadline)
                        .foregroundStyle(ForgiaPalette.mutedText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 26)
                .padding(.horizontal, 22)

                VStack(alignment: .leading, spacing: 24) {
                    InlineBalanceHistoryCard(scopeContoIDs: scopeContoIDs, interval: interval, currency: currency)

                    if report.expenses > 0 {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Ricorrenti e variabili").font(.headline)
                            periodAmount("Ricorrenti", amount: report.recurring)
                            periodAmount("Variabili", amount: report.variable)
                            Text("Solo spese registrate nel periodo selezionato; le ricorrenze sono quelle contrassegnate da te.")
                                .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                        }.unifiedCard()
                        categoryDistributionCard
                        VStack(alignment: .leading, spacing: 20) {
                            HStack {
                                Text("Categorie")
                                    .font(.system(.title3, design: .serif, weight: .semibold))
                                Spacer()
                                Text("Spesa registrata")
                                    .font(.caption)
                                    .foregroundStyle(ForgiaPalette.mutedText)
                            }
                            ForEach(Array(report.categories.enumerated()), id: \.offset) { index, category in
                                if let categoryID = category.categoryID {
                                    NavigationLink {
                                        TransactionListView(initialCategoryID: categoryID,
                                                            initialInterval: DateInterval(start: interval.start, end: min(interval.end, Date())), expensesOnly: true, scopeContoIDs: scopeContoIDs)
                                            #if os(iOS)
                                            .toolbar(.visible, for: .navigationBar)
                                            #endif
                                    } label: {
                                        categoryRow(category, index: index)
                                    }.buttonStyle(.plain)
                                } else {
                                    categoryRow(category, index: index)
                                }
                            }
                        }
                    } else {
                        Text("Non ci sono uscite registrate nel periodo. Importa i movimenti per vedere la ripartizione per categoria.")
                            .font(.subheadline)
                            .foregroundStyle(ForgiaPalette.mutedText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .unifiedCard()
                    }

                    if report.previousExpenses > 0 {
                        comparisonCard
                        if !report.increases.isEmpty {
                            increaseCard
                        }
                    }

                    Text("I trasferimenti tra i tuoi conti sono esclusi. I valori dipendono dai movimenti importati o registrati.")
                        .font(.caption)
                        .foregroundStyle(ForgiaPalette.mutedText)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
        }
        .themedBackground()
        .safeAreaBar(edge: .top, spacing: 0) {
            SpendingPeriodBar(
                period: $period,
                title: periodTitle,
                coverage: "\(formattedDay(interval.start)) – \(formattedDay(min(Date(), interval.end.addingTimeInterval(-1))))",
                canMoveForward: interval.end <= Date(),
                move: movePeriod,
                chooseCustom: { showingCustomPeriod = true }
            )
        }
        .sheet(isPresented: $showingCustomPeriod) {
            SpendingDateRangeEditor(start: customStart, end: customEnd) { start, end in
                customStart = start
                customEnd = end
                period = nil
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .presentationContentInteraction(.scrolls)
        }
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }

    private func categoryRow(_ category: CategoryOutflow, index: Int) -> some View {
        SpendingBarRow(category: category, currency: currency, largestAmount: largestAmount,
                       color: SpendingChartPalette.color(at: index), total: report.expenses)
    }

    private var periodTitle: String {
        switch period {
        case .month: anchor.formatted(.dateTime.month(.wide).year().locale(locale))
        case .year: anchor.formatted(.dateTime.year().locale(locale))
        case .quarter: "\((Calendar.current.component(.month, from: anchor) - 1) / 3 + 1)° trimestre · \(anchor.formatted(.dateTime.year().locale(locale)))"
        case .week, nil:
            "\(formattedDay(interval.start)) – \(formattedDay(interval.end.addingTimeInterval(-1)))"
        }
    }

    private func formattedDay(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year().locale(locale))
    }

    private func movePeriod(_ offset: Int) {
        guard let period else { return }
        anchor = period.moving(interval.start, by: offset)
    }

    private var comparisonCard: some View {
        let change = report.expenses - report.previousExpenses
        return VStack(alignment: .leading, spacing: 13) {
            Text("Confronto").font(.headline)
            HStack(alignment: .top, spacing: 16) {
                periodAmount("Periodo precedente", amount: report.previousExpenses)
                Rectangle().fill(ForgiaPalette.border).frame(width: 1, height: 50)
                periodAmount("Periodo selezionato", amount: report.expenses)
            }
            Text(change > 0
                 ? "Hai speso \(change.formatted(.currency(code: currency).locale(locale))) in più rispetto al periodo precedente."
                 : change < 0
                 ? "Hai speso \(abs(change).formatted(.currency(code: currency).locale(locale))) in meno rispetto al periodo precedente."
                 : "La spesa è uguale al periodo precedente.")
                .font(.subheadline)
                .foregroundStyle(ForgiaPalette.mutedText)
        }
        .unifiedCard()
    }

    private var increaseCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Cosa è aumentato").font(.headline)
            ForEach(Array(report.increases.enumerated()), id: \.offset) { _, category in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(category.name).font(.subheadline.weight(.semibold))
                        Text("\(category.previous.formatted(.currency(code: currency).locale(locale))) → \(category.current.formatted(.currency(code: currency).locale(locale)))")
                            .font(.caption)
                            .foregroundStyle(ForgiaPalette.mutedText)
                    }
                    Spacer(minLength: 8)
                    Text("+\(category.increase.formatted(.currency(code: currency).locale(locale)))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ForgiaPalette.accent)
                        .monospacedDigit()
                }
            }
            Text("Il confronto usa il periodo precedente; per il periodo corrente considera solo la porzione già trascorsa. Controlla nei movimenti se l'aumento deriva da una spesa abituale o occasionale.")
                .font(.caption)
                .foregroundStyle(ForgiaPalette.mutedText)
        }
        .unifiedCard()
    }

    private func periodAmount(_ title: String, amount: Decimal) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption)
                .foregroundStyle(ForgiaPalette.mutedText)
                .fixedSize(horizontal: false, vertical: true)
            Text(amount, format: .currency(code: currency))
                .font(.system(.headline, design: .rounded, weight: .bold))
                .minimumScaleFactor(0.75)
                .lineLimit(1)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var categoryDistributionCard: some View {
        let slices = report.chartOutflows
        return VStack(spacing: 12) {
            Chart {
                ForEach(Array(slices.enumerated()), id: \.offset) { index, category in
                    SectorMark(
                        angle: .value("Uscite", NSDecimalNumber(decimal: category.amount).doubleValue),
                        innerRadius: .ratio(0.66),
                        angularInset: 2
                    )
                    .foregroundStyle(SpendingChartPalette.color(at: index))
                    .accessibilityLabel(category.name)
                    .accessibilityValue(category.amount.formatted(.currency(code: currency).locale(locale)))
                }
            }
            .chartLegend(.hidden)
            .frame(height: 225)
            .overlay {
                VStack(spacing: 3) {
                    Text(report.expenses, format: .currency(code: currency))
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text("TOTALE USCITE")
                        .font(.caption2.weight(.semibold))
                        .tracking(0.6)
                        .foregroundStyle(ForgiaPalette.mutedText)
                }
                .frame(width: 138)
                .accessibilityHidden(true)
            }
            Text("Prime cinque categorie e resto")
                .font(.caption)
                .foregroundStyle(ForgiaPalette.mutedText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

private enum SpendingChartPalette {
    static func color(at index: Int) -> Color {
        switch index % 6 {
        case 1: Color(red: 0.48, green: 0.64, blue: 0.70)
        case 2: Color(red: 0.79, green: 0.60, blue: 0.47)
        case 3: Color(red: 0.63, green: 0.59, blue: 0.73)
        case 4: Color(red: 0.66, green: 0.71, blue: 0.53)
        case 5: Color(red: 0.55, green: 0.59, blue: 0.62)
        default: ForgiaPalette.accent
        }
    }
}

private struct SpendingBarRow: View {
    let category: CategoryOutflow
    let currency: String
    let largestAmount: Decimal
    let color: Color
    let total: Decimal

    private var fraction: CGFloat {
        guard largestAmount > 0 else { return 0 }
        return CGFloat(truncating: NSDecimalNumber(decimal: category.amount / largestAmount))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(category.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(NSDecimalNumber(decimal: category.amount / total).doubleValue, format: .percent.precision(.fractionLength(0)))
                    .font(.caption)
                    .foregroundStyle(ForgiaPalette.mutedText)
                Text(category.amount, format: .currency(code: currency))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
            GeometryReader { geometry in
                Capsule().fill(ForgiaPalette.border.opacity(0.75))
                    .overlay(alignment: .leading) {
                        Capsule().fill(color)
                            .frame(width: max(2, geometry.size.width * fraction))
                    }
            }
            .frame(height: 5)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SpendingDateRangeEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var start: Date
    @State var end: Date
    let apply: (Date, Date) -> Void

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Dal", selection: $start, in: ...end, displayedComponents: .date)
                DatePicker("Al", selection: $end, in: start...Date(), displayedComponents: .date)
                Text("Le date sono incluse. Il confronto considera un intervallo precedente con lo stesso numero di giorni; per oggi usa solo la parte già trascorsa.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("Scegli date")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Applica") {
                        apply(start, end)
                        dismiss()
                    }
                    .disabled(SpendingAnalysisWindow(start: start, endInclusive: end) == nil)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 300)
        #endif
    }
}

private struct SpendingPeriodBar: View {
    @Binding var period: SpendingAnalysisPeriod?
    let title: String
    let coverage: String
    let canMoveForward: Bool
    let move: (Int) -> Void
    let chooseCustom: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 8) {
                if period != nil {
                    Button { move(-1) } label: {
                        Image(systemName: "chevron.left")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                    .frame(width: 44, height: 44)
                    .accessibilityLabel("Periodo precedente")
                }
                Spacer(minLength: 0)
                Menu {
                    ForEach(SpendingAnalysisPeriod.allCases, id: \.self) { value in
                        Button { period = value } label: {
                            if period == value { Label(value.displayName, systemImage: "checkmark") }
                            else { Text(value.displayName) }
                        }
                    }
                    Divider()
                    Button("Personalizzato…", action: chooseCustom)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .hidden()
                        Text(title)
                            .font(.system(.title3, design: .serif, weight: .semibold))
                            .multilineTextAlignment(.center)
                        Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                    }
                    .frame(minHeight: 44)
                }
                .accessibilityIdentifier("analysis-period-picker")
                Spacer(minLength: 0)
                if period != nil {
                    Button { move(1) } label: {
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                    .frame(width: 44, height: 44)
                    .accessibilityLabel("Periodo successivo")
                    .disabled(!canMoveForward)
                    .opacity(canMoveForward ? 1 : 0.4)
                }
            }
            Text(coverage)
                .font(.caption)
                .foregroundStyle(ForgiaPalette.mutedText)
                .multilineTextAlignment(.center)
        }
        .tint(ForgiaPalette.accent)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }
}
