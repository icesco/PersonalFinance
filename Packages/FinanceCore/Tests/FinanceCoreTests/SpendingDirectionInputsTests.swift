import Foundation
import Testing
@testable import FinanceCore

@MainActor
struct SpendingDirectionInputsTests {
    private func date(_ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
    }

    private func entry(_ amount: Decimal, _ type: TransactionType, _ date: Date, _ conto: Conto) -> Transaction {
        let value = Transaction(amount: amount, type: type, date: date)
        if type == .income { value.setToConto(conto) }
        else { value.setFromConto(conto) }
        return value
    }

    @Test func balancesUseOnlyMaturedEntriesAndRespectTransferDestinationCurrency() {
        let cash = Conto(name: "Banca", type: .checking, initialBalance: 1_000)
        let card = Conto(name: "Carta", type: .credit, initialBalance: -100)
        let foreign = Conto(name: "Altro libro", type: .checking)
        let transfer = entry(100, .transfer, date(9, 19), foreign)
        transfer.setToConto(cash)
        transfer.destinationAmount = 90
        let transactions = [
            entry(50, .expense, date(9, 19), cash),
            entry(20, .expense, date(9, 20), card), transfer,
            entry(2_000, .income, date(9, 25), cash),
            entry(200, .expense, date(9, 23), cash),
            entry(300, .expense, date(9, 24), card),
            entry(900, .expense, date(9, 21), foreign)
        ]
        let inputs = SpendingDirectionInputs.build(conti: [cash, card], transactions: transactions + [transfer],
                                                   resolutions: [], now: date(9, 20), horizon: date(10, 31))
        #expect(inputs.liquidBalance == 1_040)
        #expect(inputs.creditDebt == 120)
        #expect(inputs.planned.count == 3)
        #expect(inputs.planned.allSatisfy { !$0.isRecurring })
        #expect(inputs.transactions.count == 6)
    }

    @Test func futureRecurringSeedAndSubsequentOccurrencesAppearExactlyOnce() {
        let cash = Conto(name: "Banca", type: .checking, initialBalance: 500)
        let seed = entry(80, .expense, date(9, 25), cash)
        seed.isRecurring = true
        seed.recurrenceFrequency = .monthly
        let inputs = SpendingDirectionInputs.build(conti: [cash], transactions: [seed], resolutions: [],
                                                   now: date(9, 20), horizon: date(10, 31))
        #expect(inputs.liquidBalance == 500)
        #expect(inputs.planned.map(\.date) == [date(9, 25), date(10, 25)])
        #expect(inputs.planned.allSatisfy { $0.isRecurring })
    }

    @Test func materializedOccurrenceWithoutResolutionAndSkippedDatesAreNotProjectedAgain() {
        let cash = Conto(name: "Banca", type: .checking, initialBalance: 500)
        let seed = entry(80, .expense, date(9, 1), cash)
        seed.isRecurring = true
        seed.recurrenceFrequency = .monthly
        let recorded = entry(85, .expense, date(10, 2), cash)
        recorded.recurrenceSourceID = seed.id
        recorded.externalID = RecurrenceResolution.key(sourceID: seed.id, date: date(10, 1))
        let skipped = RecurrenceResolution(sourceID: seed.id, scheduledDate: date(11, 1), isSkipped: true)
        let inputs = SpendingDirectionInputs.build(conti: [cash], transactions: [seed, recorded], resolutions: [skipped],
                                                   now: date(9, 20), horizon: date(11, 2))
        #expect(inputs.liquidBalance == 420)
        #expect(inputs.planned.count == 1)
        #expect(inputs.planned.first?.date == date(10, 2))
        #expect(inputs.planned.first?.amount == 85)
        #expect(inputs.planned.first?.isRecurring == true)
    }

    @Test func oneTimeFutureIncomeEndsTheEstimateWithoutInflatingSpendableBalance() {
        let cash = Conto(name: "Banca", type: .checking, initialBalance: 1_000)
        let history = [date(7, 1), date(7, 15), date(8, 5), date(8, 15), date(9, 19)]
            .map { entry(20, .expense, $0, cash) }
        let future = [entry(2_000, .income, date(9, 30), cash), entry(200, .expense, date(9, 25), cash)]
        let inputs = SpendingDirectionInputs.build(conti: [cash], transactions: history + future, resolutions: [],
                                                   now: date(9, 20), horizon: date(10, 31))
        let result = SpendingDirectionCalculator.calculate(transactions: inputs.transactions, planned: inputs.planned,
                                                           liquidBalance: inputs.liquidBalance, creditDebt: inputs.creditDebt,
                                                           balancesVerified: inputs.balancesVerified, now: date(9, 20))
        #expect(result.availability == .ready)
        #expect(result.nextIncome?.date == date(9, 30))
        #expect(result.liquidBalance == 900)
        #expect(result.recentIncome == 0)
        #expect(result.committedOutgoings == 200)
        #expect(result.upcoming30DaysRecurringExpenses == 0)
        #expect(result.estimatedMargin! < 700)
        #expect(result.estimatedMargin! > 0)
    }
}
