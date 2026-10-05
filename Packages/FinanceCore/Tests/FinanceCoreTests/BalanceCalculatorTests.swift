import Testing
import Foundation
@testable import FinanceCore

// MARK: - Test Helpers

private let contoA = UUID()
private let contoB = UUID()
private let contoC = UUID()

private func tx(
    _ amount: Decimal,
    _ type: TransactionType,
    _ date: Date,
    from: UUID? = nil,
    to: UUID? = nil
) -> TransactionSnapshot {
    TransactionSnapshot(
        amount: amount,
        type: type,
        date: date,
        fromContoId: from,
        toContoId: to
    )
}

private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
    var components = DateComponents()
    components.year = y
    components.month = m
    components.day = d
    components.hour = 12
    return Calendar.current.date(from: components)!
}

private let defaultContiIDs: Set<UUID> = [contoA, contoB]

// MARK: - netChange

@Suite("netChange")
struct NetChangeTests {

    @Test("Income to conto in set adds amount")
    func incomeToContoInSet() {
        let t = tx(500, .income, date(2025, 1, 15), to: contoA)
        #expect(BalanceCalculator.netChange(for: t, contiIDs: defaultContiIDs) == 500)
    }

    @Test("Income to external conto returns 0")
    func incomeToExternalConto() {
        let t = tx(500, .income, date(2025, 1, 15), to: contoC)
        #expect(BalanceCalculator.netChange(for: t, contiIDs: defaultContiIDs) == 0)
    }

    @Test("Expense from conto in set subtracts amount")
    func expenseFromContoInSet() {
        let t = tx(200, .expense, date(2025, 1, 15), from: contoA)
        #expect(BalanceCalculator.netChange(for: t, contiIDs: defaultContiIDs) == -200)
    }

    @Test("Expense from external conto returns 0")
    func expenseFromExternalConto() {
        let t = tx(200, .expense, date(2025, 1, 15), from: contoC)
        #expect(BalanceCalculator.netChange(for: t, contiIDs: defaultContiIDs) == 0)
    }

    @Test("Transfer out (from set to external) subtracts amount")
    func transferOut() {
        let t = tx(300, .transfer, date(2025, 1, 15), from: contoA, to: contoC)
        #expect(BalanceCalculator.netChange(for: t, contiIDs: defaultContiIDs) == -300)
    }

    @Test("Transfer in (from external to set) adds amount")
    func transferIn() {
        let t = tx(300, .transfer, date(2025, 1, 15), from: contoC, to: contoA)
        #expect(BalanceCalculator.netChange(for: t, contiIDs: defaultContiIDs) == 300)
    }

    @Test("Transfer internal (both in set) cancels out to 0")
    func transferInternal() {
        let t = tx(300, .transfer, date(2025, 1, 15), from: contoA, to: contoB)
        #expect(BalanceCalculator.netChange(for: t, contiIDs: defaultContiIDs) == 0)
    }

    @Test("Transfer external (neither in set) returns 0")
    func transferExternal() {
        let externalA = UUID()
        let externalB = UUID()
        let t = tx(300, .transfer, date(2025, 1, 15), from: externalA, to: externalB)
        #expect(BalanceCalculator.netChange(for: t, contiIDs: defaultContiIDs) == 0)
    }

    @Test("Zero amount returns 0")
    func zeroAmount() {
        let t = tx(0, .income, date(2025, 1, 15), to: contoA)
        #expect(BalanceCalculator.netChange(for: t, contiIDs: defaultContiIDs) == 0)
    }
}

// MARK: - chartYDomain

@Suite("chartYDomain")
struct ChartYDomainTests {

    @Test("No data returns 0...100")
    func noData() {
        let domain = BalanceCalculator.chartYDomain(dataPoints: [])
        #expect(domain == 0...100)
    }

    @Test("Single point gets ±50 range")
    func singlePoint() {
        let points = [BalanceDataPoint(date: date(2025, 1, 1), balance: 1000)]
        let domain = BalanceCalculator.chartYDomain(dataPoints: points)
        #expect(domain == 950...1050)
    }

    @Test("Range with 10% padding")
    func rangeWithPadding() {
        let points = [
            BalanceDataPoint(date: date(2025, 1, 1), balance: 1000),
            BalanceDataPoint(date: date(2025, 2, 1), balance: 2000)
        ]
        let domain = BalanceCalculator.chartYDomain(dataPoints: points)
        // Range 1000, padding 100. Lower: max(0, 1000-100) = 900, Upper: 2000+100 = 2100
        #expect(domain.lowerBound == 900)
        #expect(domain.upperBound == 2100)
    }

    @Test("Negative values")
    func negativeValues() {
        let points = [
            BalanceDataPoint(date: date(2025, 1, 1), balance: -500),
            BalanceDataPoint(date: date(2025, 2, 1), balance: -100)
        ]
        let domain = BalanceCalculator.chartYDomain(dataPoints: points)
        // Range 400, padding 40. Lower: -500-40 = -540, Upper: -100+40 = -60
        #expect(domain.lowerBound == -540)
        #expect(domain.upperBound == -60)
    }

    @Test("Mixed positive and negative")
    func mixedValues() {
        let points = [
            BalanceDataPoint(date: date(2025, 1, 1), balance: -200),
            BalanceDataPoint(date: date(2025, 2, 1), balance: 800)
        ]
        let domain = BalanceCalculator.chartYDomain(dataPoints: points)
        // Range 1000, padding 100. Lower: -200-100 = -300 (negative, so no clamping), Upper: 800+100 = 900
        #expect(domain.lowerBound == -300)
        #expect(domain.upperBound == 900)
    }

    @Test("Positive lower bound clamped to 0")
    func positiveLowerBoundClampedToZero() {
        let points = [
            BalanceDataPoint(date: date(2025, 1, 1), balance: 50),
            BalanceDataPoint(date: date(2025, 2, 1), balance: 150)
        ]
        let domain = BalanceCalculator.chartYDomain(dataPoints: points)
        // Range 100, padding 10. Lower: max(0, 50-10) = 40, Upper: 150+10 = 160
        #expect(domain.lowerBound == 40)
        #expect(domain.upperBound == 160)
    }

    @Test("Equal points get ±50 range")
    func equalPoints() {
        let points = [
            BalanceDataPoint(date: date(2025, 1, 1), balance: 500),
            BalanceDataPoint(date: date(2025, 2, 1), balance: 500)
        ]
        let domain = BalanceCalculator.chartYDomain(dataPoints: points)
        #expect(domain == 450...550)
    }
}
