import Foundation
import SwiftData
import Testing
@testable import FinanceCore

@MainActor
struct MonthlyForecastTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Rome")!
        return value
    }
    private func date(_ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: .init(year: 2026, month: month, day: day, hour: hour))!
    }
    private func expense(_ conto: Conto, _ month: Int, _ day: Int, _ amount: Decimal = 30) -> Transaction {
        let row = Transaction(amount: amount, type: .expense, date: date(month, day))
        row.createdAt = row.date
        row.scheduledOriginDate = nil
        row.setFromConto(conto)
        return row
    }
    private func history(_ conto: Conto) -> [Transaction] {
        [expense(conto, 6, 30, 1)] + (7...9).flatMap { month in
            [expense(conto, month, 5), expense(conto, month, 20)]
        }
    }
    private func report(_ conto: Conto, _ rows: [Transaction], month: Int = 10, resolutions: [RecurrenceResolution] = []) -> MonthlyForecast {
        MonthlyForecastCalculator.build(conto: conto, transactions: rows, resolutions: resolutions,
            month: date(month, 10), now: date(10, 10), calendar: calendar)
    }

    @Test func accountScopeBoundariesAndNoInventedIncome() {
        let conto = Conto(name: "Cointestato", type: .checking, initialBalance: 200)
        let other = Conto(name: "Crédit Agricole", type: .checking, initialBalance: 900)
        let paid = expense(conto, 10, 1, 20)
        let planned = expense(conto, 10, 31, 40)
        let wrongEndpoint = expense(other, 10, 4, 500)
        wrongEndpoint.setToConto(conto)
        let result = report(conto, [paid, paid, planned, expense(conto, 11, 1, 60), expense(other, 10, 2, 100), wrongEndpoint])
        #expect(MonthlyForecast.total(result.recorded) == 20)
        #expect(result.certainRemaining == 40)
        #expect(result.income.isEmpty)
        #expect(result.balance == 180)
        #expect(result.variableRemaining == nil)
        #expect(result.remaining == nil)
        #expect(result.necessary(includingVariables: false) == 40)
        let reserve = MonthlySafetyMargin(necessary: result.necessary(includingVariables: false),
                                          mode: .percentage, value: 10, currency: "EUR")
        #expect(reserve?.requiredWithReserve == 44)
        #expect(result.monthTotal(includingVariables: false) == 60)
    }

    @Test func estimatesSubtractRecordedAndScheduledInSameCategory() throws {
        let conto = Conto(name: "Corrente", type: .checking, initialBalance: 1000)
        let paid = expense(conto, 10, 9, 10)
        let scheduled = expense(conto, 10, 25, 20)
        let alreadyPaidBill = expense(conto, 10, 3, 15)
        alreadyPaidBill.scheduledOriginDate = alreadyPaidBill.date
        let result = report(conto, history(conto) + [paid, scheduled, alreadyPaidBill])
        #expect(result.estimateLimitation == nil)
        let estimate = try #require(result.estimates.first)
        #expect(estimate.samples.count == 6)
        #expect(estimate.monthlyBaseline == 60)
        #expect(estimate.alreadyRecorded == 10)
        #expect(estimate.scheduled == 35)
        #expect(estimate.remaining == 15)
        #expect(result.remaining == 35)
        #expect(result.monthTotal == 60)
        #expect(result.recordedOccasional.count == 1)
        #expect(result.recordedUnscheduled.count == 1)
    }

    @Test func plannedHistoryExcludedAndEstimateNeverNegative() {
        let conto = Conto(name: "Corrente", type: .checking, initialBalance: 1000)
        let bill = expense(conto, 8, 22, 2000)
        bill.scheduledOriginDate = bill.date
        let huge = expense(conto, 10, 20, 500)
        let result = report(conto, history(conto) + [bill, expense(conto, 10, 9, 10), huge])
        #expect(result.estimates.first?.monthlyBaseline == 60)
        #expect(result.variableRemaining == 0)
        #expect(result.remaining == 500)
    }

    @Test func skippedAndMaterializedRecurrencesOverdueAndEndedSeries() throws {
        let conto = Conto(name: "Corrente", type: .checking, initialBalance: 1000)
        let source = expense(conto, 9, 3, 50)
        source.isRecurring = true
        source.recurrenceFrequency = .weekly
        source.recurrenceEndDate = date(10, 20)
        let dates = source.recurrenceDates(after: date(10, 1, 0), through: date(11, 1, 0))
        let first = try #require(dates.first)
        let second = try #require(dates.dropFirst().first)
        let realized = expense(conto, 10, 2, 50)
        realized.recurrenceSourceID = source.id
        // Payment date can change; externalID retains the occurrence date.
        realized.externalID = RecurrenceResolution.key(sourceID: source.id, date: first)
        let skipped = RecurrenceResolution(sourceID: source.id, scheduledDate: second, isSkipped: true)
        let result = report(conto, [source, realized], resolutions: [skipped])
        #expect(result.recurring.count == dates.count - 2)
        #expect(MonthlyForecast.total(result.recorded) == 50)
        #expect(result.recurring.allSatisfy { $0.date <= date(10, 20) })
        let unresolved = report(conto, [source])
        #expect(unresolved.recurring.contains { $0.date <= date(10, 10) })
    }

    @Test func transfersAffectBalanceAndCoverageNotConsumption() {
        let conto = Conto(name: "Corrente", type: .checking, initialBalance: 100)
        let other = Conto(name: "Altro", type: .checking, initialBalance: 1000)
        let recordedTransfer = Transaction.createTransfer(amount: 20, fromConto: other, toConto: conto, date: date(10, 1))
        let incoming = Transaction.createTransfer(amount: 50, fromConto: other, toConto: conto, date: date(10, 11))
        incoming.destinationAmount = 45
        let outgoing = Transaction.createTransfer(amount: 30, fromConto: conto, toConto: other, date: date(10, 13))
        let result = report(conto, [recordedTransfer, incoming, outgoing, expense(conto, 10, 12, 180)])
        #expect(result.balance == 120)
        #expect(result.transfers.count == 2)
        #expect(MonthlyForecast.total(result.transfers) == 15)
        #expect(result.certainRemaining == 180)
        #expect(result.income.isEmpty)
        #expect(result.deadlineShortfall == 45)
    }

    @Test func incomeAfterDeadlineCannotHideEarlierShortfall() {
        let conto = Conto(name: "Corrente", type: .checking, initialBalance: 100)
        let income = Transaction(amount: 500, type: .income, date: date(10, 20))
        income.setToConto(conto)
        let source = Transaction(amount: 900, type: .income, date: date(9, 3), isRecurring: true, recurrenceFrequency: .monthly)
        source.setToConto(conto)
        let result = report(conto, [expense(conto, 10, 11, 150), income, source])
        // Original income is already in the recorded balance. Offset it to isolate the overdue occurrence.
        let offset = expense(conto, 9, 4, 900)
        let isolated = report(conto, [offset, expense(conto, 10, 11, 150), income, source])
        #expect(result.income.count == 2)
        #expect(isolated.balance == 100)
        #expect(isolated.deadlineShortfall == 50)
    }

    @Test func pastAndFutureDoNotUseCurrentBalanceForCoverage() {
        let conto = Conto(name: "Corrente", type: .checking, initialBalance: 1000)
        let rows = history(conto) + [expense(conto, 10, 9, 10), expense(conto, 11, 3, 20)]
        let past = report(conto, rows, month: 9)
        let future = report(conto, rows, month: 11)
        #expect(past.period == .past)
        #expect(past.monthTotal == 60)
        #expect(past.variableRemaining == nil)
        #expect(past.deadlineShortfall == nil)
        #expect(future.period == .future)
        #expect(future.remaining == 60)
        #expect(future.deadlineShortfall == nil)
        #expect(future.estimatedShortfall == nil)
    }

    @Test func missingAndInvalidAmountsAndCreditNeverProduceFalseCoverage() {
        let conto = Conto(name: "Corrente", type: .checking, initialBalance: 1000)
        let invalid = expense(conto, 10, 20)
        invalid.amount = nil
        let result = report(conto, history(conto) + [expense(conto, 10, 9), invalid])
        #expect(result.certainRemaining == nil)
        #expect(result.variableRemaining == nil)
        #expect(result.deadlineShortfall == nil)
        conto.initialBalance = nil
        #expect(report(conto, []).balance == nil)
        conto.initialBalance = 1000
        conto.type = .credit
        #expect(report(conto, []).deadlineShortfall == nil)
        let negative = expense(conto, 10, 20, -10)
        #expect(report(conto, [negative]).certainRemaining == nil)
    }


    @Test func estimateUsesMedianWithZeroMonthsAndDoesNotOffsetOtherCategories() throws {
        let conto = Conto(name: "Corrente", type: .checking, initialBalance: 1000)
        let food = Category(name: "Alimentari", icon: "basket")
        let bills = Category(name: "Bollette", icon: "bolt")
        let rows = [expense(conto, 6, 30)] + (7...8).flatMap { month in
            (1...3).map { expense(conto, month, $0, 10) }
        }
        for row in rows { row.setCategory(food) }
        let scheduled = expense(conto, 10, 20, 100)
        scheduled.setCategory(bills)
        let paid = expense(conto, 10, 9, 5)
        paid.setCategory(food)
        let result = report(conto, rows + [scheduled, paid])
        #expect(result.estimateLimitation == nil)
        #expect(result.estimates.first?.monthlyBaseline == 30)
        #expect(result.estimates.first?.scheduled == 0)
        #expect(result.variableRemaining == 25)
        #expect(result.remaining == 125)
    }

    @Test func staleOrInvalidPaidScheduledHistoryWithholdsEstimate() {
        let conto = Conto(name: "Corrente", type: .checking, initialBalance: 1000)
        let stale = history(conto).filter { $0.date < date(9, 10) }
        #expect(report(conto, stale).variableRemaining == nil)
        let bill = expense(conto, 10, 9)
        bill.scheduledOriginDate = bill.date
        bill.amount = nil
        #expect(report(conto, history(conto) + [bill]).variableRemaining == nil)
    }

    @Test func provenancePersistsInModelAndSharedExport() throws {
        let conto = Conto(name: "Corrente", type: .checking, initialBalance: 1000)
        let bill = expense(conto, 10, 20, 200)
        bill.scheduledOriginDate = bill.date
        bill.date = date(10, 9)
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let book = Account(name: "Comune", currency: "EUR")
        conto.account = book
        book.conti = [conto]
        container.mainContext.insert(book)
        container.mainContext.insert(conto)
        container.mainContext.insert(bill)
        try container.mainContext.save()
        let saved = try #require(container.mainContext.fetch(FetchDescriptor<Transaction>()).first)
        #expect(saved.scheduledOriginDate == date(10, 20))
        #expect(report(conto, [saved]).recordedOccasional.count == 1)
        let export = try SharedBookExporter.export(bookID: book.id, container: container)
        let target = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let scope = SharedBookScope(ownerName: "fixture-owner", bookID: book.id)
        try SharedBookImporter.apply(scope: scope, records: export.records, assets: export.assets, container: target)
        let imported = try #require(target.mainContext.fetch(FetchDescriptor<Transaction>()).first)
        #expect(imported.scheduledOriginDate == date(10, 20))
        #expect(imported.date == date(10, 9))
    }

    @Test func jointAccountCommitmentsStaySeparateFromImportedHistoryAndExtraordinaryPurchases() throws {
        func decimal(_ value: String) -> Decimal { Decimal(string: value)! }
        let conto = Conto(name: "Comune", type: .checking, initialBalance: decimal("1237.44"))
        let food = Category(name: "Spesa alimentare", icon: "basket")
        let mortgage = Category(name: "Casa", icon: "house")
        let loan = Category(name: "Prestito", icon: "banknote")
        let fees = Category(name: "Commissioni", icon: "creditcard")
        let phone = Category(name: "Telefono", icon: "phone")
        let parents = Category(name: "Famiglia", icon: "figure.2")
        let purchases = Category(name: "Arredi", icon: "sofa")
        let contributions = Category(name: "Categoria mista", icon: "arrow.left.arrow.right")
        let water = Category(name: "Acqua", icon: "drop")
        func row(_ month: Int, _ day: Int, _ amount: Decimal, _ category: FinanceCore.Category) -> Transaction {
            let result = expense(conto, month, day, amount)
            result.setCategory(category)
            return result
        }
        let recurringTerms: [(FinanceCore.Category, Decimal, Int)] = [(mortgage, decimal("412.84"), 24), (loan, decimal("29.82"), 24),
                                                         (fees, 1, 19), (fees, 1, 20), (phone, decimal("36.79"), 8)]
        let sources = recurringTerms.map { category, amount, day in
            let source = row(10, day, amount, category)
            source.isRecurring = true
            source.recurrenceFrequency = .monthly
            return source
        }
        let imports = (7...9).flatMap { month in
            recurringTerms.map { category, amount, day in row(month, day, amount, category) }
        }
        let incoming = Transaction(amount: 500, type: .income, date: date(9, 1))
        incoming.setToConto(conto); incoming.setCategory(contributions)
        let grocery = [row(6, 30, 1, food), row(8, 10, decimal("186.88"), food), row(8, 11, decimal("66.31"), food), row(9, 11, decimal("215.75"), food)]
        let occasionalHistory = [row(7, 7, 1405, parents), row(8, 5, 112, parents), row(9, 3, 865, purchases)]
        let externalTransfers = [row(7, 8, 321, contributions), row(8, 7, 110, contributions), row(9, 8, 144, contributions)]
        let planned = [row(10, 25, 120, parents), row(10, 25, 92, parents), row(10, 25, 25, parents), row(10, 28, decimal("75.59"), water)]
        let result = report(conto, sources + imports + grocery + occasionalHistory + externalTransfers + planned + [incoming])
        #expect(result.certainRemaining == 757.25)
        #expect(result.necessary(includingVariables: false) == 757.25)
        #expect(result.estimateLimitation == nil)
        #expect(result.estimates.count == 1)
        #expect(result.estimates.first?.id == food.id.uuidString)
        #expect(result.variableRemaining == 215.75)
        #expect(result.necessary(includingVariables: true) == 973)
        #expect(result.historyExclusions.first { $0.reason == .recurringPayment }?.events.count == 15)
        #expect(MonthlyForecast.total(try #require(result.historyExclusions.first { $0.reason == .mixedCategory }).events) == 575)
        #expect(MonthlyForecast.total(try #require(result.historyExclusions.first { $0.reason == .sporadic }).events) == 2382)
        #expect(imports.allSatisfy { $0.recurrenceSourceID == nil && $0.isRecurring != true })
    }

    @Test func leafCategoriesDoNotDeductAnUnrelatedBillAndAnExceptionalMonthDoesNotSetTheBaseline() throws {
        let conto = Conto(name: "Corrente", type: .checking, initialBalance: 1000)
        let macro = Category(name: "Essenziali", icon: "house")
        let groceries = Category(name: "Spesa", icon: "basket", parentCategoryId: macro.id)
        let bills = Category(name: "Fatture", icon: "doc", parentCategoryId: macro.id)
        var rows = [expense(conto, 6, 30)]
        rows[0].setCategory(groceries)
        for month in 7...9 {
            let row = expense(conto, month, 5, month == 7 ? 1405 : 100)
            row.setCategory(groceries); rows.append(row)
        }
        let bill = expense(conto, 10, 25, 300)
        bill.setCategory(bills)
        let paid = expense(conto, 10, 9, 20)
        paid.setCategory(groceries)
        let result = report(conto, rows + [paid, bill])
        #expect(result.estimates.first?.monthlyBaseline == 100)
        #expect(result.estimates.first?.scheduled == 0)
        #expect(result.variableRemaining == 80)
        #expect(result.necessary(includingVariables: false) == 300)
        #expect(result.necessary(includingVariables: true) == 380)
    }

    @Test func inferredRecurringHistoryUsesAccountLeafAmountAndOnePaymentPerOccurrence() throws {
        let conto = Conto(name: "Uno", type: .checking)
        let other = Conto(name: "Due", type: .checking)
        let fees = Category(name: "Costi", icon: "creditcard")
        let shopping = Category(name: "Acquisti", icon: "bag")
        let source = expense(conto, 10, 19, 1)
        source.setCategory(fees); source.isRecurring = true; source.recurrenceFrequency = .monthly
        let matches = (7...9).map { month in
            let row = expense(conto, month, 21, 1); row.setCategory(fees); return row
        }
        let extra = expense(conto, 7, 22, 1); extra.setCategory(fees)
        let samePriceElsewhere = expense(conto, 8, 19, 1); samePriceElsewhere.setCategory(shopping)
        let otherAccount = expense(other, 9, 19, 1); otherAccount.setCategory(fees)
        let result = report(conto, [source, extra, samePriceElsewhere, otherAccount] + matches)
        let excluded = try #require(result.historyExclusions.first { $0.reason == .recurringPayment }).events
        #expect(Set(excluded.map(\.transactionID)) == Set(matches.map(\.id)))
        #expect(result.certainRemaining == 1)
        #expect(result.necessary(includingVariables: false) == 1)
        #expect(result.necessary(includingVariables: true) == nil)
    }
}
