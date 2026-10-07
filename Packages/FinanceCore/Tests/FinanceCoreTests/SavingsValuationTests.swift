import Foundation
import SwiftData
import Testing
@testable import FinanceCore

struct SavingsValuationTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private func date(_ month: Int, _ day: Int = 1, year: Int = 2025) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
    private func close(_ a: Decimal, _ b: Decimal) -> Bool { abs(a - b) < Decimal(string: "0.000001")! }

    @Test func rateChangesApplyOnlyFromTheirEffectiveDates() {
        let start = date(1), mid = date(7), end = date(1, year: 2026)
        let result = SavingsValuation.value(initialBalance: 10000, start: start,
            rates: [.init(effectiveDate: start, annualPercent: 2), .init(effectiveDate: mid, annualPercent: 4)], movements: [], at: end, calendar: calendar)
        #expect(close(result.pendingInterest, 10000 * (Decimal(181) * 2 + Decimal(184) * 4) / 365 / 100))
        let historical = SavingsValuation.value(initialBalance: 10000, start: start,
            rates: [.init(effectiveDate: start, annualPercent: 2), .init(effectiveDate: mid, annualPercent: 4)], movements: [], at: mid, calendar: calendar)
        #expect(close(historical.pendingInterest, 200 * Decimal(181) / 365))
    }

    @Test func depositsWithdrawalsAndFutureEntriesUseTheirActualDates() {
        let start = date(1), mid = date(7), end = date(1, year: 2026)
        let value = SavingsValuation.value(initialBalance: 1000, start: start,
            rates: [.init(effectiveDate: start, annualPercent: 10)],
            movements: [.init(date: mid, amount: 1000), .init(date: date(10), amount: -500),
                        .init(date: date(2, year: 2026), amount: 9000)], at: end, calendar: calendar)
        #expect(value.capital == 1500)
        #expect(close(value.pendingInterest, (1000 * Decimal(181) + 2000 * Decimal(92) + 1500 * Decimal(92)) / 365 / 10))
    }

    @Test func creditedInterestReplacesEstimateAndOnlyThenCapitalizes() {
        let start = date(1), mid = date(7), end = date(1, year: 2026)
        let expectedCredit = Decimal(1000) * 10 / 100 * 181 / 365
        let value = SavingsValuation.value(initialBalance: 1000, start: start,
            rates: [.init(effectiveDate: start, annualPercent: 10)],
            movements: [.init(date: mid, amount: expectedCredit, isInterest: true)], at: end, calendar: calendar)
        #expect(value.capital == 1000)
        #expect(value.creditedInterest == expectedCredit)
        #expect(close(value.pendingInterest, (1000 + expectedCredit) * 10 / 100 * 184 / 365))
        #expect(close(value.estimatedValue, 1000 + expectedCredit + value.pendingInterest))
    }

    @Test func leapYearAndNoRate() {
        let start = date(1, year: 2024), end = date(1, year: 2025)
        let annual = SavingsValuation.value(initialBalance: 1000, start: start,
            rates: [.init(effectiveDate: start, annualPercent: 5)], movements: [], at: end, calendar: calendar)
        #expect(close(annual.pendingInterest, 50))
        let noRate = SavingsValuation.value(initialBalance: 1000, start: start, rates: [], movements: [], at: end, calendar: calendar)
        #expect(noRate.estimatedValue == 1000)
    }

    @MainActor @Test func goalReflectsEditsDeletionAndInternalTransfersWithoutDuplicates() throws {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let context = container.mainContext
        let book = Account(name: "Test")
        let first = Conto(name: "Savings A", type: .savings, initialBalance: 1000)
        let second = Conto(name: "Savings B", type: .savings, initialBalance: 0)
        let checking = Conto(name: "Checking", type: .checking)
        book.conti = [first, second, checking]; context.insert(book)
        try SavingsAccountEdits.linkGoal(conto: first, existingID: nil, target: 2000, context: context)
        let goal = try #require(first.linkedSavingsGoal)
        try SavingsAccountEdits.linkGoal(conto: second, existingID: goal.id, target: 2000, context: context)
        let transfer = Transaction(amount: 200, type: .transfer, date: date(1))
        transfer.setFromConto(first); transfer.setToConto(second); context.insert(transfer)
        let deposit = Transaction(amount: 100, type: .transfer, date: date(1))
        deposit.setFromConto(checking); deposit.setToConto(first); context.insert(deposit)
        let interest = Transaction(amount: 25, type: .income, date: date(1))
        interest.isSavingsInterest = true; interest.setToConto(first); context.insert(interest)
        try context.save()
        #expect(goal.fundedAmount == 1100)
        #expect(abs(goal.progressPercentage - 55) < 0.000001)
        deposit.amount = 300; try context.save()
        #expect(goal.fundedAmount == 1300)
        context.delete(deposit); try context.save()
        #expect(goal.fundedAmount == 1000)
        context.delete(transfer); try context.save()
        #expect(goal.fundedAmount == 1000)
    }

    @MainActor @Test func persistedRatesAndSeriesKeepSeparateCapitalAndValue() throws {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let context = container.mainContext
        let conto = Conto(name: "Savings", type: .savings, initialBalance: 1000)
        context.insert(conto)
        let start = date(1), end = date(1, year: 2026)
        try conto.setSavingsRate(5, effectiveDate: start)
        try conto.setSavingsRate(3, effectiveDate: date(7))
        try conto.setSavingsRate(4, effectiveDate: date(7))
        try context.save()
        let fetched = try #require(ModelContext(container).fetch(FetchDescriptor<Conto>()).first)
        #expect(fetched.savingsRates.count == 2)
        #expect(fetched.savingsRates.last?.annualPercent == 4)
        let series = try #require(AccountBalanceSeries.make(conti: [fetched], selectedIDs: [fetched.id], transactions: [], resolutions: [], interval: DateInterval(start: start, end: end), now: end).first)
        #expect(series.points.last?.balance == 1000)
        #expect(series.savingsCapital?.last?.balance == 1000)
        #expect((series.savingsValue?.last?.balance ?? 0) > 1000)
        #expect(series.savingsValue?.count ?? 0 > 300)
    }
    @MainActor @Test func sharingPreservesRateHistoryInterestAndGoalLinkWithRemappedIDs() throws {
        let source = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let context = source.mainContext
        let book = Account(name: "Shared savings")
        let conto = Conto(name: "Savings", type: .savings, initialBalance: 1000)
        conto.account = book; book.conti = [conto]; context.insert(book)
        try conto.setSavingsRate(4, effectiveDate: date(1))
        try SavingsAccountEdits.linkGoal(conto: conto, existingID: nil, target: 2000, context: context)
        let interest = Transaction(amount: 20, type: .income, date: date(7))
        interest.setToConto(conto); interest.isSavingsInterest = true; context.insert(interest)
        try context.save()
        let snapshot = try SharedBookExporter.export(bookID: book.id, container: source)
        let target = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let scope = SharedBookScope(ownerName: "savings-owner", bookID: book.id)
        try SharedBookImporter.apply(scope: scope, records: snapshot.records, assets: snapshot.assets, container: target)
        let verify = ModelContext(target)
        let imported = try #require(verify.fetch(FetchDescriptor<Conto>()).first)
        let importedGoal = try #require(imported.linkedSavingsGoal)
        #expect(imported.savingsGoalID == importedGoal.id)
        #expect(importedGoal.id != conto.savingsGoalID)
        #expect(imported.savingsRates == conto.savingsRates)
        #expect(try verify.fetch(FetchDescriptor<Transaction>()).first?.isSavingsInterest == true)
        #expect(importedGoal.fundedAmount == 1000)
    }

    @MainActor @Test func onboardingCreatesLinkedGoalAndFailureLeavesNoGoal() throws {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let context = container.mainContext
        let conto = Conto(name: "Savings", type: .savings, initialBalance: 500, annualInterestRate: 3, savingsGoal: 1000)
        let book = try AccountCreation(context: context).create(name: "Test", currency: "EUR", conti: [conto])
        #expect(book.savingsGoals?.count == 1)
        #expect(conto.linkedSavingsGoal?.fundedAmount == 500)
        #expect(conto.savingsRates.count == 1)
        enum Failure: Error { case save }
        let failed = Conto(name: "Failed", type: .savings, savingsGoal: 2000)
        let service = AccountCreation(context: context, save: { throw Failure.save })
        #expect(throws: Failure.self) { try service.create(name: "Failed", currency: "EUR", conti: [failed]) }
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<SavingsGoal>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<Account>()) == 1)
    }

    @Test func negativeReturnReducesValueWithoutReducingContributedCapital() {
        let start = date(1), end = date(1, year: 2026)
        let result = SavingsValuation.value(initialBalance: 10000, start: start,
            rates: [.init(effectiveDate: start, annualPercent: -5)], movements: [], at: end, calendar: calendar)
        #expect(result.capital == 10000)
        #expect(close(result.pendingInterest, -500))
        #expect(close(result.estimatedValue, 9500))
    }

    @Test func lossesAndGainsAcrossRateChangesAreNetAndHistorical() {
        let start = date(1), mid = date(7), end = date(1, year: 2026)
        let rates: [SavingsRate] = [.init(effectiveDate: start, annualPercent: -5), .init(effectiveDate: mid, annualPercent: 2)]
        let historical = SavingsValuation.value(initialBalance: 10000, start: start, rates: rates, movements: [], at: mid, calendar: calendar)
        #expect(close(historical.pendingInterest, -500 * Decimal(181) / 365))
        let result = SavingsValuation.value(initialBalance: 10000, start: start, rates: rates, movements: [], at: end, calendar: calendar)
        #expect(close(result.pendingInterest, (-500 * Decimal(181) + 200 * Decimal(184)) / 365))
        #expect(result.capital == 10000)
    }

    @MainActor @Test func negativeRatesPersistAndGoalStillTracksContributions() throws {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let context = container.mainContext
        let conto = Conto(name: "Savings", type: .savings, initialBalance: 10000)
        let book = Account(name: "Test"); book.conti = [conto]; conto.account = book; context.insert(book)
        try conto.setSavingsRate(-5, effectiveDate: date(1))
        try SavingsAccountEdits.linkGoal(conto: conto, existingID: nil, target: 20000, context: context)
        try context.save()
        let verify = ModelContext(container)
        let saved = try #require(verify.fetch(FetchDescriptor<Conto>()).first)
        #expect(saved.savingsRates.first?.annualPercent == -5)
        #expect(saved.savingsSnapshot(at: date(1, year: 2026)).estimatedValue < 10000)
        #expect(saved.linkedSavingsGoal?.fundedAmount == 10000)
    }

}
