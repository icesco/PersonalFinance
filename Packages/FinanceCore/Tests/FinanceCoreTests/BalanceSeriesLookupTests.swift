import Foundation
import Testing
@testable import FinanceCore

struct BalanceSeriesLookupTests {
    private let origin = Date(timeIntervalSince1970: 1_800_000_000)

    private func points(_ offsets: [Int], seed: Int) -> [BalanceDataPoint] {
        offsets.enumerated().map { index, offset in
            BalanceDataPoint(date: origin.addingTimeInterval(Double(offset)),
                             balance: Decimal((index * 173 + seed) % 401 - 200) / 7)
        }
    }

    private func reference(_ account: AccountBalanceSeries, at date: Date) -> Decimal {
        let history = date > (account.points.last?.date ?? date) && !account.projected.isEmpty ? account.projected : account.points
        return history.last { $0.date <= date }?.balance ?? history.first?.balance ?? 0
    }

    @Test func binaryLookupMatchesLinearReferenceAtBoundariesAndDuplicateDates() {
        for recorded in [[], [0], [0, 0, 10, 20, 20, 30]] {
            for projected in [[], [30], [30, 30, 40, 60, 60]] {
                var account = AccountBalanceSeries(id: UUID(), name: "Test", colorHex: "000000",
                    points: points(recorded, seed: 1), projected: points(projected, seed: 2))
                account.savingsCapital = points(recorded, seed: 3)
                account.savingsValue = points(projected, seed: 4)
                for offset in -1...70 {
                    let date = origin.addingTimeInterval(Double(offset))
                    #expect(account.balance(at: date) == reference(account, at: date))
                    for estimated in [false, true] {
                        let values = estimated ? account.savingsValue : account.savingsCapital
                        #expect(account.savingsAmount(at: date, estimated: estimated) == values?.last { $0.date <= date }?.balance)
                    }
                }
                account.savingsValue = nil
                #expect(account.savingsAmount(at: origin, estimated: true) == nil)
            }
        }
    }

    @Test func chronologicalWidgetTotalsMatchIndependentLinearSums() {
        let accounts = (0..<8).map { index in
            AccountBalanceSeries(id: UUID(), name: "\(index)", colorHex: "000000",
                points: points(index == 0 ? [] : [0, 5, 5, 10, 20, 30], seed: index),
                projected: points(index % 3 == 0 ? [] : [30, 35, 35, 45, 70], seed: index * 7))
        }
        let snapshot = WidgetBalanceSnapshot(period: .month,
            interval: DateInterval(start: origin.addingTimeInterval(-5), end: origin.addingTimeInterval(75)),
            recordedAt: origin.addingTimeInterval(30), series: accounts)
        let recordedDates = Set(accounts.flatMap { $0.points.map(\.date) } + [snapshot.interval.start, snapshot.recordedAt])
            .filter { $0 >= snapshot.interval.start && $0 <= snapshot.recordedAt }.sorted()
        let projectedDates = Set(accounts.flatMap { $0.projected.map(\.date) } + [snapshot.recordedAt, snapshot.interval.end])
            .filter { $0 >= snapshot.recordedAt && $0 <= snapshot.interval.end }.sorted()
        for (actual, dates) in [(snapshot.totalPoints, recordedDates), (snapshot.totalProjected, projectedDates)] {
            let expected = dates.map { date in
                BalanceDataPoint(date: date, balance: accounts.reduce(Decimal.zero) { $0 + reference($1, at: date) })
            }
            #expect(actual.map(\.date) == expected.map(\.date))
            #expect(actual.map(\.balance) == expected.map(\.balance))
        }
    }
}
