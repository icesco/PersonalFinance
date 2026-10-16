import FinanceCore
import SwiftUI
import WidgetKit

enum FinanceBalanceWidgetSize {
    case small, medium, large, extraLarge, extraLargePortrait
}

/// Widget presentation shared with the app's visual verification screen.
struct FinanceBalanceWidgetContent: View {
    let history: WidgetBalanceSnapshot
    let bookName: String
    let currency: String
    var size: FinanceBalanceWidgetSize = .large
    var showLegend = true
    @Environment(\.financeWidgetTheme) private var theme
    private var singleAccountTint: Color? {
        history.series.count == 1 ? BalanceWidgetTint.color(theme, history: history) : nil
    }

    var body: some View {
        content.foregroundStyle(singleAccountTint ?? .primary)
    }

    @ViewBuilder private var content: some View {
        if size == .small {
            FinanceBalanceSmallContent(history: history, bookName: bookName, currency: currency)
        } else if size == .extraLarge {
            FinanceBalanceExtraLargeContent(history: history, bookName: bookName, currency: currency, showLegend: showLegend)
        } else if size == .extraLargePortrait {
            FinanceBalancePortraitContent(history: history, bookName: bookName, currency: currency, showLegend: showLegend)
        } else if size == .medium {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .bottom, spacing: 8) {
                    Text(history.recordedTotal, format: .currency(code: currency))
                        .contentTransition(.numericText())
                        .font(.system(size: 32, weight: .bold)).monospacedDigit()
                        .financeWidgetForeground(theme.palette.accent)
                        .lineLimit(1).minimumScaleFactor(0.65).layoutPriority(1)
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 3) {
                        BalanceWidgetPeriodLabel(history: history)
                            .font(.caption2.weight(.semibold))
                        Text("Previsto: \(history.projectedTotal.formatted(.currency(code: currency)))")
                            .contentTransition(.numericText())
                            .font(.caption2).monospacedDigit()
                    }
                    .foregroundStyle(BalanceWidgetTint.secondary(theme, history: history))
                    .lineLimit(1).minimumScaleFactor(0.7)
                }
                BalanceHistoryPlot(series: history.series, interval: history.interval, currency: currency,
                                   selectedDate: .constant(nil), compact: true, interactive: false, snapshotLabel: true,
                                   colorOverride: singleAccountTint, lineWidth: 2.5, showsSnapshotLabel: false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack(spacing: 6) {
                    if showLegend {
                    HStack(spacing: 6) {
                        ForEach(Array(history.series.prefix(2))) { account in
                            HStack(spacing: 3) {
                                BalanceAccountLegendKey(account: account, series: history.series, compact: true)
                                Text(account.name).lineLimit(1)
                            }
                        }
                        if history.series.count > 2 { Text("+\(history.series.count - 2)") }
                    }.font(.caption2.weight(.medium)).foregroundStyle(BalanceWidgetTint.secondary(theme, history: history))
                    }
                    Spacer(minLength: 0)
                    FinanceWidgetFreshness(generatedAt: history.recordedAt, now: Date())
                    Image("FormiMark").resizable().widgetAccentedRenderingMode(.accented).scaledToFit()
                        .frame(width: 14, height: 14)
                        .financeWidgetForeground(theme.palette.accent)
                        .accessibilityHidden(true)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                BalanceWidgetHeader(history: history)
                HStack(alignment: .firstTextBaseline) {
                    Text(history.recordedTotal, format: .currency(code: currency))
                        .contentTransition(.numericText())
                        .font(.system(size: 36, weight: .bold)).monospacedDigit()
                        .financeWidgetForeground(theme.palette.accent)
                        .lineLimit(1).minimumScaleFactor(0.65).layoutPriority(1)
                    Spacer(minLength: 6)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Previsto").font(.caption2).foregroundStyle(BalanceWidgetTint.secondary(theme, history: history))
                        Text(history.projectedTotal, format: .currency(code: currency))
                            .contentTransition(.numericText())
                            .font(.caption.weight(.semibold)).monospacedDigit().lineLimit(1)
                    }
                }
                BalanceHistoryPlot(series: history.series, interval: history.interval, currency: currency,
                                   selectedDate: .constant(nil), interactive: false, snapshotLabel: true,
                                   colorOverride: singleAccountTint)
                    .frame(maxHeight: .infinity)
                if showLegend {
                VStack(spacing: 5) {
                    ForEach(Array(history.series.prefix(4))) { account in
                        HStack(spacing: 6) {
                            BalanceAccountLegendKey(account: account, series: history.series)
                            Text(account.name).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(account.balance(at: history.recordedAt), format: .currency(code: currency))
                                .contentTransition(.numericText())
                                .monospacedDigit().lineLimit(1)
                        }.font(.caption2)
                        .accessibilityElement(children: .combine)
                    }
                    if history.series.count > 4 {
                        Text("Altri \(history.series.count - 4) conti nel grafico")
                            .font(.caption2).foregroundStyle(BalanceWidgetTint.secondary(theme, history: history))
                    }
                }
                }
                HStack {
                    Text("Tratteggio: previsto")
                    Spacer(minLength: 4)
                    Text(history.recordedAt, format: .dateTime.day().month().hour().minute())
                }.font(.caption2).foregroundStyle(BalanceWidgetTint.secondary(theme, history: history)).lineLimit(1)
            }
        }
    }
}

/// The balance widget's identity colour, shared by its header and background.
struct BalanceWidgetTint {
    static func color(_ theme: AppTheme, history: WidgetBalanceSnapshot? = nil) -> Color {
        guard let history, history.series.count == 1 else { return theme.palette.accent }
        return FinanceCategoryColor.color(hex: history.series.first?.colorHex, fallback: theme.palette.accent)
    }

    static func secondary(_ theme: AppTheme, history: WidgetBalanceSnapshot) -> Color {
        history.series.count == 1 ? color(theme, history: history) : theme.palette.mutedText
    }
}

private struct BalanceWidgetHeader: View {
    let history: WidgetBalanceSnapshot
    var compact = false
    @Environment(\.financeWidgetTheme) private var theme
    var body: some View {
        HStack(spacing: 6) {
            BalanceWidgetPeriodLabel(history: history)
                .font(.system(compact ? .subheadline : .headline, design: .rounded, weight: compact ? .medium : .semibold))
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Image("FormiMark").resizable().widgetAccentedRenderingMode(.accented).scaledToFit()
                .frame(width: compact ? 16 : 20, height: compact ? 16 : 20)
                .accessibilityHidden(true)
        }.financeWidgetForeground(BalanceWidgetTint.color(theme, history: history))
    }
}

private struct BalanceWidgetPeriodLabel: View {
    let history: WidgetBalanceSnapshot
    var body: some View {
        switch history.period {
        case .week:
            Text("\(history.interval.start, format: .dateTime.day().month(.abbreviated)) – \(history.interval.end.addingTimeInterval(-1), format: .dateTime.day().month(.abbreviated))")
        case .month:
            Text(history.interval.start, format: .dateTime.month(.wide).year())
        case .quarter:
            Text("\(history.interval.start, format: .dateTime.month(.abbreviated)) – \(history.interval.end.addingTimeInterval(-1), format: .dateTime.month(.abbreviated).year())")
        case .year:
            Text(history.interval.start, format: .dateTime.year())
        }
    }
}

private struct FinanceBalanceSmallContent: View {
    let history: WidgetBalanceSnapshot
    let bookName: String
    let currency: String
    @Environment(\.financeWidgetTheme) private var theme

    private var combined: Bool { history.series.count > 2 }
    private var chartSeries: [AccountBalanceSeries] {
        guard combined, let first = history.series.first else { return history.series }
        return [AccountBalanceSeries(id: first.id, name: bookName,
                                     colorHex: first.colorHex,
                                     points: history.totalPoints, projected: history.totalProjected)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            BalanceWidgetHeader(history: history, compact: true)
            Text(history.recordedTotal, format: .currency(code: currency))
                .contentTransition(.numericText())
                .font(.system(size: 30, weight: .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
                .financeWidgetForeground(theme.palette.accent)
                .layoutPriority(1)
            BalanceHistoryPlot(series: chartSeries, interval: history.interval, currency: currency,
                               selectedDate: .constant(nil), compact: true, interactive: false,
                               snapshotLabel: true, minimal: true,
                               colorOverride: combined || history.series.count == 1 ? BalanceWidgetTint.color(theme, history: history) : nil)
                .frame(maxHeight: .infinity)
                .accessibilityLabel(combined ? "Saldo totale registrato e previsto" : "Saldo registrato e previsto per conto")
        }
    }
}

private struct FinanceBalanceExtraLargeContent: View {
    let history: WidgetBalanceSnapshot
    let bookName: String
    let currency: String
    var showLegend = true
    var body: some View {
        BalanceWidgetExpandedContent(history: history, currency: currency, showLegend: showLegend, portrait: false)
    }
}

private struct FinanceBalancePortraitContent: View {
    let history: WidgetBalanceSnapshot
    let bookName: String
    let currency: String
    var showLegend = true
    var body: some View {
        BalanceWidgetExpandedContent(history: history, currency: currency, showLegend: showLegend, portrait: true)
    }
}

private struct BalanceWidgetExpandedContent: View {
    let history: WidgetBalanceSnapshot
    let currency: String
    let showLegend: Bool
    let portrait: Bool
    @Environment(\.financeWidgetTheme) private var theme
    @Environment(\.calendar) private var calendar

    var body: some View {
        VStack(alignment: .leading, spacing: portrait ? 12 : 10) {
            BalanceWidgetHeader(history: history)
            if portrait {
                balances
                flows
                chart
                minimum
                BalanceWidgetUpcomingMovements(history: history, currency: currency, portrait: true)
            } else {
                GeometryReader { geometry in
                    HStack(alignment: .top, spacing: 24) {
                        VStack(alignment: .leading, spacing: 10) {
                            balances
                            chart
                            minimum
                        }.frame(width: (geometry.size.width - 24) * 0.66, height: geometry.size.height)
                        VStack(alignment: .leading, spacing: 14) {
                            flows
                            BalanceWidgetUpcomingMovements(history: history, currency: currency, portrait: false)
                        }.frame(width: (geometry.size.width - 24) * 0.34, height: geometry.size.height)
                    }
                }
            }
            if !portrait {
                HStack(spacing: 12) {
                    if showLegend { accountLegend }
                    Text("Tratteggio: previsto")
                    Spacer(minLength: 4)
                    Text(history.recordedAt, format: .dateTime.hour().minute())
                }.font(.caption2).foregroundStyle(BalanceWidgetTint.secondary(theme, history: history)).lineLimit(1)
            }
        }
    }

    private var balances: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Saldo attuale").font(.caption).foregroundStyle(BalanceWidgetTint.secondary(theme, history: history))
                Text(history.recordedTotal, format: .currency(code: currency))
                    .contentTransition(.numericText())
                    .font(.system(size: portrait ? 48 : 44, weight: .bold)).monospacedDigit()
                    .financeWidgetForeground(theme.palette.accent)
                    .lineLimit(1).minimumScaleFactor(0.65)
            }
            .layoutPriority(1)
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text("A fine periodo").font(.caption).foregroundStyle(BalanceWidgetTint.secondary(theme, history: history))
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(history.projectedTotal, format: .currency(code: currency))
                    .contentTransition(.numericText())
                    .font(.title3.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(width: portrait ? 100 : 110, alignment: .trailing)
        }
    }

    @ViewBuilder private var flows: some View {
        if let totals = history.scheduledFlows {
            let layout = portrait
                ? AnyLayout(HStackLayout(spacing: 18))
                : AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            layout {
                flow(title: "Entrate programmate", amount: totals.incoming, icon: "arrow.down.left")
                flow(title: "Uscite programmate", amount: totals.outgoing, icon: "arrow.up.right")
            }
        }
    }

    private func flow(title: LocalizedStringKey, amount: Decimal?, icon: String) -> some View {
        let layout = portrait
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 3))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 6))
        return layout {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2.weight(.semibold))
                    .frame(width: 14, alignment: .center)
                Text(title).font(.caption2).lineLimit(1).minimumScaleFactor(0.8)
            }.foregroundStyle(BalanceWidgetTint.secondary(theme, history: history))
            if !portrait { Spacer(minLength: 0) }
            if let amount {
                Text(amount, format: .currency(code: currency)).font(.headline).monospacedDigit().lineLimit(1)
                    .contentTransition(.numericText())
            } else {
                Text("Importi incompleti").font(.caption).lineLimit(1)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
    }

    private var chart: some View {
        BalanceHistoryPlot(series: history.series, interval: history.interval, currency: currency,
            selectedDate: .constant(nil), interactive: false, snapshotLabel: true,
            colorOverride: history.series.count == 1 ? BalanceWidgetTint.color(theme, history: history) : nil)
            .padding(.top, 14).frame(maxHeight: .infinity)
    }

    private var minimum: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let low = history.minimumProjectedDailyBalance(calendar: calendar) {
                HStack(spacing: 4) {
                    Text("Minimo previsto")
                    Text(low.balance, format: .currency(code: currency)).fontWeight(.semibold)
                        .contentTransition(.numericText())
                    Text("· \(min(low.date, history.interval.end.addingTimeInterval(-1)), format: .dateTime.day().month(.abbreviated))")
                }.font(.caption2).foregroundStyle(BalanceWidgetTint.secondary(theme, history: history)).lineLimit(1).minimumScaleFactor(0.8)
            }
            if portrait && showLegend { accountLegend }
        }
    }

    private var accountLegend: some View {
        HStack(spacing: 8) {
            ForEach(Array(history.series.prefix(3))) { account in
                HStack(spacing: 3) {
                    BalanceAccountLegendKey(account: account, series: history.series, compact: true)
                    Text(account.name).lineLimit(1)
                }
            }
            if history.series.count > 3 { Text("+\(history.series.count - 3)") }
        }.font(.caption2).foregroundStyle(BalanceWidgetTint.secondary(theme, history: history))
    }
}

private struct BalanceMovementAnchors: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct BalanceWidgetUpcomingMovements: View {
    let history: WidgetBalanceSnapshot
    let currency: String
    let portrait: Bool
    @Environment(\.financeWidgetTheme) private var theme
    @Environment(\.widgetRenderingMode) private var renderingMode
    private var accountIDs: Set<UUID> { Set(history.series.map(\.id)) }

    var body: some View {
        VStack(alignment: .leading, spacing: portrait ? 10 : 14) {
            Text("Prossime scadenze").font(.subheadline.weight(.semibold))
            if let movements = history.plannedMovements {
                if movements.isEmpty {
                    Text("Nessun movimento programmato nel periodo").font(.caption).foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: portrait ? 10 : 14) {
                        ForEach(Array(movements.prefix(3))) { movement in
                            row(movement)
                        }
                    }
                    .backgroundPreferenceValue(BalanceMovementAnchors.self) { anchors in
                        GeometryReader { geometry in
                            let centers = anchors.values.map { geometry[$0] }.map { CGPoint(x: $0.midX, y: $0.midY) }.sorted { $0.y < $1.y }
                            Path { path in
                                if centers.count > 1, let first = centers.first, let last = centers.last {
                                    path.move(to: first); path.addLine(to: last)
                                }
                            }.stroke(.primary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                        }.accessibilityHidden(true).allowsHitTesting(false)
                    }
                    if let count = history.scheduledMovementCount, count > 3 {
                        Text("Altri \(count - 3) movimenti nel periodo").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Apri Formi per aggiornare le scadenze").font(.caption).foregroundStyle(.secondary)
            }
            if !portrait { Spacer(minLength: 0) }
        }
    }

    private func row(_ movement: WidgetBalancePlannedMovement) -> some View {
        let tint = FinanceCategoryColor.color(hex: movement.categoryColor, fallback: theme.palette.accent)
        let internalTransfer = movement.isInternalTransfer(accountIDs: accountIDs)
        let amount = internalTransfer ? movement.amount : movement.netChange(accountIDs: accountIDs)
        return HStack(spacing: 9) {
            Image(systemName: movement.categoryIcon ?? movement.type.icon)
                .widgetAccentedRenderingMode(.accented)
                .font(.headline).financeWidgetForeground(tint)
                .frame(width: 30, height: 32)
                .background {
                    RoundedRectangle(cornerRadius: 8).fill(renderingMode == .fullColor ? theme.palette.surface : .clear)
                        .overlay { RoundedRectangle(cornerRadius: 8).fill(renderingMode == .fullColor ? tint.opacity(0.12) : .primary.opacity(0.1)) }
                }
                .anchorPreference(key: BalanceMovementAnchors.self, value: .bounds) { [movement.id: $0] }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(movement.title.isEmpty ? (movement.type == .transfer ? "Trasferimento" : (movement.type == .income ? "Entrata" : "Spesa")) : movement.title)
                    .font(.caption.weight(.semibold)).lineLimit(1)
                Text(movement.date, format: .dateTime.day().month(.abbreviated)).font(.caption2).foregroundStyle(.secondary)
                if internalTransfer { Text("Tra i conti selezionati").font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 2)
            if let amount {
                Text((amount > 0 && !internalTransfer ? "+" : "") + amount.formatted(.currency(code: currency)))
                    .contentTransition(.numericText())
                    .font(.caption.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                    .frame(width: portrait ? 100 : 76, alignment: .trailing)
                    .layoutPriority(1)
                    .foregroundStyle(.primary)
            } else {
                Text("—").font(.caption).accessibilityLabel("Importo non disponibile")
            }
        }.accessibilityElement(children: .combine)
    }
}
