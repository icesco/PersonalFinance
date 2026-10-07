import Foundation
import Testing
@testable import FinanceCore

struct RecordedBalanceHistoryTests {
    @Test func boundariesAreUniqueAndFutureEntriesAreExcluded() {
        let conto = UUID(), start = Date(timeIntervalSince1970: 1000)
        let now = start.addingTimeInterval(100)
        let values = [
            TransactionSnapshot(amount: 10, type: .expense, date: start.addingTimeInterval(-1), fromContoId: conto),
            TransactionSnapshot(amount: 20, type: .expense, date: start, fromContoId: conto),
            TransactionSnapshot(amount: 5, type: .income, date: start, toContoId: conto),
            TransactionSnapshot(amount: 30, type: .expense, date: now.addingTimeInterval(1), fromContoId: conto)
        ]
        let result = RecordedBalanceHistory.points(transactions: values, contiIDs: [conto], initialBalance: 100,
                                                   interval: DateInterval(start: start, duration: 200), now: now)
        #expect(result.map(\.balance) == [75, 75])
        #expect(result.map(\.date) == [start, now])
        let past = RecordedBalanceHistory.points(transactions: values, contiIDs: [conto], initialBalance: 100,
                                                 interval: DateInterval(start: start.addingTimeInterval(-100), end: start), now: now)
        #expect(past.last?.balance == 90)
    }

    @Test func internalTransfersCancelAndForeignCreditUsesDestinationAmount() {
        let a = UUID(), b = UUID(), foreign = UUID(), start = Date(timeIntervalSince1970: 1000)
        let values = [
            TransactionSnapshot(amount: 20, type: .transfer, date: start.addingTimeInterval(1), fromContoId: a, toContoId: b),
            TransactionSnapshot(amount: 11, type: .transfer, date: start.addingTimeInterval(2), fromContoId: foreign, toContoId: b, destinationAmount: 10)
        ]
        let interval = DateInterval(start: start, duration: 100)
        let combined = RecordedBalanceHistory.points(transactions: values, contiIDs: [a, b], initialBalance: 100, interval: interval, now: interval.end)
        #expect(combined.last?.balance == 110)
        let single = RecordedBalanceHistory.points(transactions: values, contiIDs: [a], initialBalance: 100, interval: interval, now: interval.end)
        #expect(single.last?.balance == 80)
    }

    @Test func separateAccountsKeepTransfersAndIndependentOpeningBalances() {
        let a = UUID(), b = UUID(), idle = UUID(), outside = UUID()
        let start = Date(timeIntervalSince1970: 1000)
        let now = start.addingTimeInterval(50)
        let values = [
            TransactionSnapshot(amount: 10, type: .expense, date: start.addingTimeInterval(-1), fromContoId: a),
            TransactionSnapshot(amount: 20, type: .transfer, date: start.addingTimeInterval(1), fromContoId: a, toContoId: b),
            TransactionSnapshot(amount: 11, type: .transfer, date: start.addingTimeInterval(2), fromContoId: outside, toContoId: b, destinationAmount: 10),
            TransactionSnapshot(amount: 5, type: .expense, date: start.addingTimeInterval(2), fromContoId: b),
            TransactionSnapshot(amount: 999, type: .income, date: now.addingTimeInterval(1), toContoId: a)
        ]
        let histories = RecordedBalanceHistory.series(transactions: values,
            initialBalances: [a: 100, b: 50, idle: -10], interval: DateInterval(start: start, duration: 100), now: now)
        #expect(Set(histories.keys) == [a, b, idle])
        #expect(histories[a]?.first?.balance == 90)
        #expect(histories[a]?.last?.balance == 70)
        #expect(histories[b]?.first?.balance == 50)
        #expect(histories[b]?.last?.balance == 75)
        #expect(histories[idle]?.allSatisfy { $0.balance == -10 } == true)
        #expect(histories.values.allSatisfy { $0.last?.date == now })
        let combined = RecordedBalanceHistory.points(transactions: values, contiIDs: [a, b, idle],
            initialBalance: 140, interval: DateInterval(start: start, duration: 100), now: now)
        for point in combined {
            let total = histories.values.reduce(Decimal(0)) { total, history in
                total + (history.last { $0.date <= point.date }?.balance ?? 0)
            }
            #expect(total == point.balance)
        }
    }

    @Test func accountSeriesRespectScopeAndEmptyFuturePeriods() {
        let a = UUID(), b = UUID(), start = Date(timeIntervalSince1970: 1000)
        let values = [TransactionSnapshot(amount: 20, type: .transfer, date: start.addingTimeInterval(1), fromContoId: a, toContoId: b)]
        let interval = DateInterval(start: start, duration: 100)
        let single = RecordedBalanceHistory.series(transactions: values, initialBalances: [b: 0], interval: interval, now: interval.end)
        #expect(Set(single.keys) == [b])
        #expect(single[b]?.last?.balance == 20)
        let future = RecordedBalanceHistory.series(transactions: values, initialBalances: [a: 100], interval: interval, now: start.addingTimeInterval(-1))
        #expect(future[a]?.isEmpty == true)
        #expect(RecordedBalanceHistory.series(transactions: values, initialBalances: [:], interval: interval, now: interval.end).isEmpty)
    }

}
