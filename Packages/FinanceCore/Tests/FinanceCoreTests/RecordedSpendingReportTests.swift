import Foundation
import Testing
@testable import FinanceCore

struct RecordedSpendingReportTests {
    @Test func boundariesAndKindsStayConsistent() {
        let category = UUID()
        func entry(_ time: TimeInterval, _ amount: Decimal, _ type: TransactionType = .expense, recurring: Bool = false) -> DirectionTransaction {
            .init(date: Date(timeIntervalSince1970: time), amount: amount, type: type,
                  categoryID: category, categoryName: "Casa", isRecurring: recurring)
        }
        let report = RecordedSpendingReport.calculate(
            transactions: [entry(0, 8), entry(10, 20, recurring: true), entry(19, 5), entry(20, 300), entry(12, 900, .transfer), entry(12, 800, .income)],
            interval: .init(start: Date(timeIntervalSince1970: 10), end: Date(timeIntervalSince1970: 20)),
            previous: .init(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 10)), now: Date(timeIntervalSince1970: 30))
        #expect(report.expenses == 25)
        #expect(report.recurring == 20)
        #expect(report.variable == 5)
        #expect(report.previousExpenses == 8)
        #expect(report.increases.first?.increase == 17)
        #expect(report.categories.first?.amount == 25)
    }

    @Test func sameNamesRemainSeparateAndFutureIsExcluded() {
        let now = Date()
        let rows = (0..<7).map { index in
            DirectionTransaction(date: now.addingTimeInterval(-1), amount: Decimal(index + 1), type: .expense,
                                 categoryID: UUID(), categoryName: "Stesso nome", isRecurring: false)
        }
        let future = DirectionTransaction(date: now.addingTimeInterval(5), amount: 100, type: .expense,
                                          categoryID: UUID(), categoryName: "Futuro", isRecurring: false)
        let report = RecordedSpendingReport.calculate(transactions: rows + [future],
            interval: .init(start: now.addingTimeInterval(-10), end: now.addingTimeInterval(10)),
            previous: .init(start: now.addingTimeInterval(-20), end: now.addingTimeInterval(-10)), now: now)
        #expect(report.categories.count == 7)
        #expect(report.expenses == 28)
        #expect(report.chartOutflows.count == 6)
        #expect(report.chartOutflows.reduce(Decimal.zero) { $0 + $1.amount } == report.expenses)
    }
}
