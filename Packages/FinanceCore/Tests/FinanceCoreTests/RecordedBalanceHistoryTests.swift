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
}
