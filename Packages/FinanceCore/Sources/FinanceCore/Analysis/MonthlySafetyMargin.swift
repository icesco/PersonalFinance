import Foundation

/// A user-chosen reserve, separate from forecast spending and recorded transactions.
public struct MonthlySafetyMargin: Sendable {
    public enum Mode: String, Sendable { case percentage, fixed }
    public let mode: Mode
    public let value: Decimal
    public let reserve: Decimal?
    public let requiredWithReserve: Decimal?

    public init?(necessary: Decimal?, mode: Mode, value: Decimal, currency: String) {
        guard !value.isNaN, value >= 0, necessary.map({ !$0.isNaN && $0 >= 0 }) ?? true else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        func rounded(_ number: Decimal) -> Decimal? {
            guard !number.isNaN else { return nil }
            var number = number
            var result = Decimal.zero
            NSDecimalRound(&result, &number, formatter.maximumFractionDigits, .bankers)
            return result.isNaN ? nil : result
        }
        self.mode = mode
        self.value = value
        let amount = mode == .fixed ? value : necessary.map { $0 * value / 100 }
        let computedReserve = amount.flatMap(rounded)
        let computedTotal = necessary.flatMap { necessary in computedReserve.flatMap { rounded(necessary + $0) } }
        guard amount == nil || computedReserve != nil, necessary == nil || computedTotal != nil else { return nil }
        reserve = computedReserve
        requiredWithReserve = computedTotal
    }

    /// Reserve must survive known deadlines and the remaining variable spending by month end.
    public func shortfall(minimumBalance: Decimal?, endingBalance: Decimal?, variableRemaining: Decimal?) -> Decimal? {
        guard let reserve, let minimumBalance, let endingBalance, let variableRemaining,
              !minimumBalance.isNaN, !endingBalance.isNaN, !variableRemaining.isNaN, variableRemaining >= 0 else { return nil }
        let deadlineGap = max(0, reserve - minimumBalance)
        let monthEndGap = max(0, variableRemaining + reserve - endingBalance)
        guard !deadlineGap.isNaN, !monthEndGap.isNaN else { return nil }
        return max(deadlineGap, monthEndGap)
    }
}
