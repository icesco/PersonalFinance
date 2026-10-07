import Foundation
import Testing
@testable import FinanceCore

@MainActor
struct WidgetBalanceSnapshotTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome")!
        calendar.firstWeekday = 2
        return calendar
    }
    private func date(_ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    @Test func allPeriodsKeepAccountBalancesTransfersAndProjectionsSeparate() throws {
        let book = Account(name: "Euro", currency: "EUR")
        let a = Conto(name: "Corrente", type: .checking, initialBalance: 100)
        let b = Conto(name: "Risparmi", type: .savings, initialBalance: 50)
        book.conti = [a, b]; a.account = book; b.account = book
        let recorded = Transaction(amount: 20, type: .transfer, date: date(2))
        recorded.setFromConto(a); recorded.setToConto(b)
        let scheduled = Transaction(amount: 10, type: .transfer, date: date(9))
        scheduled.setFromConto(a); scheduled.setToConto(b)
        let income = Transaction(amount: 200, type: .income, date: date(10))
        income.setToConto(a)
        let snapshot = FinanceWidgetBuilder.build(accounts: [book], budgets: [], transactions: [recorded, scheduled, income],
                                                  resolutions: [], now: date(7), calendar: calendar)
        let histories = try #require(snapshot.books.first?.balanceHistories)
        #expect(Set(histories.map(\.period)) == Set(WidgetBalancePeriod.allCases))
        #expect(histories.allSatisfy { $0.recordedTotal == 150 && $0.projectedTotal == 350 })
        for history in histories {
            #expect(history.series.first { $0.id == a.id }?.balance(at: date(7)) == 80)
            #expect(history.series.first { $0.id == b.id }?.balance(at: date(7)) == 70)
            #expect(history.series.first { $0.id == a.id }?.balance(at: history.interval.end) == 270)
            #expect(history.series.first { $0.id == b.id }?.balance(at: history.interval.end) == 80)
            #expect(history.interval == history.period.interval(containing: date(7), calendar: calendar))
        }
        #expect(!snapshot.usable(at: snapshot.validUntil))
        #expect(snapshot.validUntil <= histories.map(\.interval.end).min()!)
    }

    @Test func persistedChartRoundTripsAndLegacySnapshotsStillDecode() throws {
        let book = Account(name: "Libro")
        let conto = Conto(name: "Banca", type: .checking, initialBalance: 125)
        conto.account = book; book.conti = [conto]
        let snapshot = FinanceWidgetBuilder.build(accounts: [book], budgets: [], transactions: [], resolutions: [], now: date(7), calendar: calendar)
        let data = try JSONEncoder().encode(snapshot)
        #expect(try JSONDecoder().decode(FinanceWidgetSnapshot.self, from: data) == snapshot)
        var legacy = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var books = try #require(legacy["books"] as? [[String: Any]])
        books[0].removeValue(forKey: "balanceHistories")
        legacy["books"] = books
        let decoded = try JSONDecoder().decode(FinanceWidgetSnapshot.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(decoded.books.first?.balanceHistories == nil)
        #expect(decoded.usable(at: date(7)))
        #expect(FinanceWidgetSnapshot.empty(.hidden).books.isEmpty)
    }

    @Test func dailySnapshotsRemainBoundedAndColorsMatchTheApp() throws {
        let bank = Conto(name: "Banca", type: .checking, initialBalance: 1000)
        let other = Conto(name: "Altro", type: .checking, initialBalance: 10)
        let values = (0..<1000).map { index in
            let transaction = Transaction(amount: 1, type: .expense, date: date(2, hour: 0).addingTimeInterval(Double(index)))
            transaction.setFromConto(bank)
            return transaction
        }
        let history = WidgetBalanceSnapshot.make(period: .month, conti: [bank, other], transactions: values,
                                                   resolutions: [], now: date(7), calendar: calendar)
        let app = AccountBalanceSeries.make(conti: [bank, other], selectedIDs: [bank.id, other.id], transactions: values,
                                             resolutions: [], interval: history.interval, now: date(7))
        #expect(history.series.allSatisfy { $0.points.count <= 4 })
        #expect(history.recordedTotal == 10)
        #expect(history.projectedTotal == 10)
        #expect(history.series.map(\.colorHex) == app.map(\.colorHex))
        #expect(history.series.map { $0.balance(at: date(7)) } == app.map { $0.balance(at: date(7)) })
    }

    @Test func balanceLinkRoundTripsToAnalysis() {
        let route = FinanceWidgetRoute(destination: .analysis, bookID: UUID())
        #expect(FinanceWidgetRoute(url: route.url) == route)
    }
}
