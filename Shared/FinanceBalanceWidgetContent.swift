import FinanceCore
import SwiftUI

enum FinanceBalanceWidgetSize {
    case small, medium, large, extraLarge, extraLargePortrait
}

/// Widget presentation shared with the app's visual verification screen.
struct FinanceBalanceWidgetContent: View {
    let history: WidgetBalanceSnapshot
    let bookName: String
    let currency: String
    var size: FinanceBalanceWidgetSize = .large

    var body: some View {
        if size == .small {
            FinanceBalanceSmallContent(history: history, bookName: bookName, currency: currency)
        } else if size == .extraLarge {
            FinanceBalanceExtraLargeContent(history: history, bookName: bookName, currency: currency)
        } else if size == .extraLargePortrait {
            FinanceBalancePortraitContent(history: history, bookName: bookName, currency: currency)
        } else if size == .medium {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Saldo per conto").font(.caption.weight(.semibold))
                    HStack(spacing: 3) {
                        Text(bookName)
                        Text("·")
                        BalanceWidgetPeriodLabel(period: history.period)
                    }.font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    Text(history.recordedTotal, format: .currency(code: currency))
                        .font(.title3.bold()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
                    Text("Previsto: \(history.projectedTotal.formatted(.currency(code: currency)))")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    Text(history.recordedAt, format: .dateTime.day().month().hour().minute())
                        .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 7) {
                    BalanceHistoryPlot(series: history.series, interval: history.interval, currency: currency,
                                       selectedDate: .constant(nil), compact: true, interactive: false, snapshotLabel: true)
                        .frame(maxHeight: .infinity)
                    HStack(spacing: 6) {
                        ForEach(Array(history.series.prefix(3))) { account in
                            HStack(spacing: 3) {
                                Circle().fill(account.color).frame(width: 4, height: 4)
                                Text(account.name).lineLimit(1)
                            }
                        }
                        if history.series.count > 3 { Text("+\(history.series.count - 3)") }
                    }.font(.system(size: 9)).foregroundStyle(.secondary)
                    Text("Tratteggio: previsto").font(.system(size: 9)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Saldo per conto").font(.subheadline.weight(.semibold))
                    Spacer(minLength: 4)
                    HStack(spacing: 3) {
                        Text(bookName)
                        Text("·")
                        BalanceWidgetPeriodLabel(period: history.period)
                    }.font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(history.recordedTotal, format: .currency(code: currency))
                        .font(.title2.bold()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
                    Spacer(minLength: 6)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Previsto").font(.caption2).foregroundStyle(.secondary)
                        Text(history.projectedTotal, format: .currency(code: currency))
                            .font(.caption.weight(.semibold)).monospacedDigit().lineLimit(1)
                    }
                }
                BalanceHistoryPlot(series: history.series, interval: history.interval, currency: currency,
                                   selectedDate: .constant(nil), interactive: false, snapshotLabel: true)
                    .frame(maxHeight: .infinity)
                VStack(spacing: 5) {
                    ForEach(Array(history.series.prefix(4))) { account in
                        HStack(spacing: 6) {
                            Capsule().fill(account.color).frame(width: 14, height: 3)
                            Text(account.name).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(account.balance(at: history.recordedAt), format: .currency(code: currency))
                                .monospacedDigit().lineLimit(1)
                        }.font(.caption2)
                        .accessibilityElement(children: .combine)
                    }
                    if history.series.count > 4 {
                        Text("Altri \(history.series.count - 4) conti nel grafico")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Text("Tratteggio: previsto")
                    Spacer(minLength: 4)
                    Text(history.recordedAt, format: .dateTime.day().month().hour().minute())
                }.font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

private struct BalanceWidgetPeriodLabel: View {
    let period: WidgetBalancePeriod
    var body: some View {
        switch period {
        case .week: Text("Settimana")
        case .month: Text("Mese")
        case .quarter: Text("Trimestre")
        case .year: Text("Anno")
        }
    }
}

private struct FinanceBalanceSmallContent: View {
    let history: WidgetBalanceSnapshot
    let bookName: String
    let currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Saldo per conto").font(.caption.weight(.semibold)).lineLimit(1)
            HStack(spacing: 3) {
                Text(bookName)
                Text("·")
                BalanceWidgetPeriodLabel(period: history.period)
            }.font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            Text(history.recordedTotal, format: .currency(code: currency))
                .font(.title3.bold()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            BalanceHistoryPlot(series: history.series, interval: history.interval, currency: currency,
                               selectedDate: .constant(nil), compact: true, interactive: false,
                               snapshotLabel: true, minimal: true)
                .frame(maxHeight: .infinity)
            Text("Previsto: \(history.projectedTotal.formatted(.currency(code: currency)))")
                .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.65)
        }
    }
}

private struct FinanceBalanceExtraLargeContent: View {
    let history: WidgetBalanceSnapshot
    let bookName: String
    let currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Saldo per conto").font(.headline)
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    Text(bookName)
                    Text("·")
                    BalanceWidgetPeriodLabel(period: history.period)
                }.font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            GeometryReader { geometry in
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(history.recordedTotal, format: .currency(code: currency))
                                .font(.largeTitle.bold()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                            Spacer(minLength: 8)
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Previsto a fine periodo").font(.caption).foregroundStyle(.secondary)
                                Text(history.projectedTotal, format: .currency(code: currency))
                                    .font(.title3.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                            }
                        }
                        BalanceHistoryPlot(series: history.series, interval: history.interval, currency: currency,
                                           selectedDate: .constant(nil), interactive: false, snapshotLabel: true)
                            .frame(maxHeight: .infinity)
                    }.frame(width: (geometry.size.width - 24) * 0.58, height: geometry.size.height)
                    FinanceBalanceAccountTable(history: history, currency: currency)
                        .frame(width: (geometry.size.width - 24) * 0.42, height: geometry.size.height)
                }
            }
            HStack {
                Text("Tratteggio: previsto da movimenti programmati")
                Spacer(minLength: 8)
                Text(history.recordedAt, format: .dateTime.day().month().hour().minute())
            }.font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

private struct FinanceBalanceAccountTable: View {
    let history: WidgetBalanceSnapshot
    let currency: String
    var fillsHeight = true

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Conti")
                Spacer(minLength: 8)
                Text("Registrato / Previsto")
            }.font(.caption).foregroundStyle(.secondary)
            ForEach(Array(history.series.prefix(6))) { account in
                HStack(alignment: .center, spacing: 8) {
                    Capsule().fill(account.color).frame(width: 14, height: 3)
                    Text(account.name).font(.caption.weight(.medium)).lineLimit(1)
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(account.balance(at: history.recordedAt), format: .currency(code: currency))
                            .font(.caption.weight(.semibold))
                        Text(account.balance(at: history.interval.end), format: .currency(code: currency))
                            .font(.caption2).foregroundStyle(.secondary)
                    }.monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
                }.accessibilityElement(children: .combine)
            }
            if history.series.count > 6 {
                Text("Altri \(history.series.count - 6) conti nel grafico")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if fillsHeight { Spacer(minLength: 0) }
        }
    }
}

private struct FinanceBalancePortraitContent: View {
    let history: WidgetBalanceSnapshot
    let bookName: String
    let currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Saldo per conto").font(.headline)
                Spacer(minLength: 4)
                BalanceWidgetPeriodLabel(period: history.period)
                    .font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(bookName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(history.recordedTotal, format: .currency(code: currency))
                    .font(.largeTitle.bold()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                HStack {
                    Text("Previsto a fine periodo").foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Text(history.projectedTotal, format: .currency(code: currency))
                        .fontWeight(.semibold).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                }.font(.caption)
            }
            BalanceHistoryPlot(series: history.series, interval: history.interval, currency: currency,
                               selectedDate: .constant(nil), interactive: false, snapshotLabel: true)
                .frame(maxHeight: .infinity)
            FinanceBalanceAccountTable(history: history, currency: currency, fillsHeight: false)
            VStack(alignment: .leading, spacing: 4) {
                Text("Tratteggio: previsto da movimenti programmati")
                Text(history.recordedAt, format: .dateTime.day().month().hour().minute())
            }.font(.caption2).foregroundStyle(.secondary)
        }
    }
}
