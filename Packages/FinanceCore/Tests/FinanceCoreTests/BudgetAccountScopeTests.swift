import Foundation
import SwiftData
import Testing
@testable import FinanceCore

@MainActor
struct BudgetAccountScopeTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Rome")!
        return value
    }
    private func date(_ month: Int, _ day: Int) -> Date {
        calendar.date(from: .init(year: 2026, month: month, day: day, hour: 12))!
    }
    private func fixture() throws -> (ModelContainer, Account, Conto, Conto, FinanceCore.Category) {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let book = Account(name: "Casa", currency: "EUR")
        let joint = Conto(name: "Cointestato", type: .checking, initialBalance: 0)
        let personal = Conto(name: "Privato", type: .checking, initialBalance: 1000)
        joint.account = book; personal.account = book; book.conti = [joint, personal]
        let food = FinanceCore.Category(name: "Supermercato", icon: "basket"); food.account = book
        container.mainContext.insert(book); container.mainContext.insert(food)
        try container.mainContext.save()
        return (container, book, joint, personal, food)
    }
    private func expense(_ conto: Conto, _ category: FinanceCore.Category, _ amount: Decimal, _ month: Int, _ day: Int) -> Transaction {
        let row = Transaction(amount: amount, type: .expense, date: date(month, day))
        row.createdAt = date(month, day); row.scheduledOriginDate = nil
        row.setFromConto(conto); row.setCategory(category)
        return row
    }
    private func budget(_ book: Account, _ conto: Conto?, _ category: FinanceCore.Category, amount: Decimal = 400) -> Budget {
        let value = Budget(name: "Spesa casa", amount: amount, period: .monthly)
        value.account = book; value.contoID = conto?.id; value.categories = [category]
        return value
    }
    private func forecast(_ conto: Conto, rows: [Transaction], budgets: [Budget], month: Int = 10) -> MonthlyForecast {
        MonthlyForecastCalculator.build(conto: conto, transactions: rows, resolutions: [], month: date(month, 1),
            now: date(10, 15), calendar: calendar, budgets: budgets)
    }

    @Test func oldBudgetsStayBookWideAndScopedBudgetsFilterEveryConsumer() throws {
        let (container, book, joint, personal, food) = try fixture()
        let all = budget(book, nil, food)
        let scoped = budget(book, joint, food)
        container.mainContext.insert(all); container.mainContext.insert(scoped)
        let first = expense(joint, food, 50, 10, 5), second = expense(personal, food, 90, 10, 6)
        container.mainContext.insert(first); container.mainContext.insert(second)
        try container.mainContext.save()
        let interval = calendar.dateInterval(of: .month, for: date(10, 1))!
        #expect(RecordedBudgetSpending.total(for: all, transactions: [first, second], start: interval.start, end: interval.end) == 140)
        #expect(scoped.recordedExpenses(for: (interval.start, interval.end), transactions: [first, second]).map(\.id) == [first.id])
        #expect(BudgetOutlook.calculate(for: scoped, transactions: [first, second], now: date(10, 15), calendar: calendar).dailyAllowance == 350 / Decimal(17))
        let previews = BudgetService.previewExpense(amount: 10, categoryID: food.id, accountID: book.id,
            date: date(10, 15), budgets: [all, scoped], transactions: [first, second], calendar: calendar, contoID: personal.id)
        #expect(previews.map(\.id) == [all.id])
        let jointPreviews = BudgetService.previewExpense(amount: 10, categoryID: food.id, accountID: book.id,
            date: date(10, 15), budgets: [scoped], transactions: [first, second], calendar: calendar, contoID: joint.id)
        #expect(jointPreviews.first?.spent == 50)
        let saved = try #require(ModelContext(container).fetch(FetchDescriptor<Budget>()).first { $0.id == scoped.id })
        #expect(saved.contoID == joint.id)
        scoped.contoID = UUID()
        #expect(scoped.coveredContoIDs.isEmpty)
        #expect(RecordedBudgetSpending.total(for: scoped, transactions: [first, second], start: interval.start, end: interval.end) == 0)
    }

    @Test func scopedEditsValidateBoundaryAndRollBackScopeOnSaveFailure() throws {
        let (container, book, joint, _, food) = try fixture()
        let edits = BudgetEdits(context: container.mainContext)
        let value = try edits.apply(account: book, name: "Spesa", amountText: "400", period: .monthly,
            threshold: 0.8, categories: [food], contoID: joint.id)
        #expect(value.contoID == joint.id)
        #expect(throws: BudgetEdits.Failure.self) {
            try edits.apply(to: value, account: book, name: "Spesa", amountText: "400", period: .monthly,
                threshold: 0.8, categories: [food], contoID: UUID())
        }
        enum SaveFailure: Error { case failed }
        let failing = BudgetEdits(context: container.mainContext, save: { throw SaveFailure.failed })
        #expect(throws: SaveFailure.self) {
            try failing.apply(to: value, account: book, name: "Changed", amountText: "500", period: .weekly,
                threshold: 0.9, categories: [food], contoID: nil)
        }
        #expect(value.contoID == joint.id && value.amount == 400 && value.name == "Spesa")
    }

    @Test func monthlyBudgetReplacesHistoryAndDeductsRecordedAndPendingOnce() throws {
        let (container, book, joint, personal, food) = try fixture()
        defer { withExtendedLifetime(container) {} }
        let history = [expense(joint, food, 1, 6, 1)] + (7...9).flatMap { month in
            [expense(joint, food, 100, month, 5), expense(joint, food, 100, month, 20)]
        }
        let paid = expense(joint, food, 50, 10, 5)
        let planned = expense(joint, food, 30, 10, 25)
        let recurring = expense(joint, food, 20, 10, 27)
        recurring.isRecurring = true; recurring.recurrenceFrequency = .monthly
        let other = expense(personal, food, 999, 10, 5)
        let value = budget(book, joint, food)
        let rows = history + [paid, planned, recurring, other]
        let report = forecast(joint, rows: rows, budgets: [value, budget(book, nil, food), budget(book, personal, food)])
        #expect(report.estimates.count == 1)
        #expect(report.estimates.first?.budgetID == value.id)
        #expect(report.estimates.first?.alreadyRecorded == 50)
        #expect(report.estimates.first?.scheduled == 50)
        #expect(report.variableRemaining == 300)
        #expect(report.necessary(includingVariables: true) == 350)
        #expect(report.monthTotal(includingVariables: true) == 400)
        for row in rows { container.mainContext.insert(row) }
        container.mainContext.insert(value)
        try container.mainContext.save()
        let snapshot = try MonthlyForecastSnapshotReader.read(in: container.mainContext, contoID: joint.id,
            month: date(10, 1), now: date(10, 15), calendar: calendar)
        #expect(snapshot.variableRemaining == 300)
        let excluded = report.excludingVariableCategories(["budget:\(value.id.uuidString)"])
        #expect(excluded.variableRemaining == 0 && excluded.certainRemaining == 50)
        #expect(forecast(joint, rows: rows, budgets: [], month: 11).estimates.first?.monthlyBaseline == 200)
        #expect(forecast(joint, rows: rows, budgets: [value], month: 11).estimates.first?.monthlyBaseline == 400)
    }

    @Test func budgetWorksWithoutHistoryOverrunsDoNotBecomeNegativeAndOverlapNeedsChoice() throws {
        let (container, book, joint, _, food) = try fixture()
        defer { withExtendedLifetime(container) {} }
        let rows = [expense(joint, food, 450, 10, 5), expense(joint, food, 30, 10, 25)]
        let first = budget(book, joint, food)
        let report = forecast(joint, rows: rows, budgets: [first])
        #expect(report.historyLimitation != nil && report.estimateLimitation == nil)
        #expect(report.variableRemaining == 0 && report.remaining == 30)
        let second = budget(book, joint, food, amount: 500)
        let overlap = forecast(joint, rows: rows, budgets: [first, second])
        #expect(overlap.estimateLimitation != nil && overlap.variableRemaining == nil)
        #expect(overlap.excludingVariableCategories(["budget:\(first.id.uuidString)"]).variableRemaining == 20)
        second.period = .yearly
        #expect(forecast(joint, rows: rows, budgets: [first, second]).estimates.count == 1)
        first.amount = nil
        #expect(forecast(joint, rows: rows, budgets: [first]).variableRemaining == nil)
    }

    @Test func oneBudgetEnvelopeCoversMultipleChildrenAndLeavesOtherHistoryAvailable() throws {
        let (container, book, joint, _, food) = try fixture()
        defer { withExtendedLifetime(container) {} }
        let parent = FinanceCore.Category(name: "Casa")
        let fuel = FinanceCore.Category(name: "Carburante", parentCategoryId: parent.id)
        let other = FinanceCore.Category(name: "Altro")
        for category in [parent, fuel, other] { category.account = book; container.mainContext.insert(category) }
        food.parentCategoryId = parent.id
        let value = budget(book, joint, parent, amount: 200)
        let history = [expense(joint, other, 1, 6, 1)] + (7...9).flatMap { month in
            [expense(joint, other, 10, month, 5), expense(joint, other, 10, month, 20)]
        }
        let rows = history + [expense(joint, food, 50, 10, 5), expense(joint, fuel, 30, 10, 6),
                              expense(joint, fuel, 20, 10, 25), expense(joint, food, 40, 10, 26)]
        let result = forecast(joint, rows: rows, budgets: [value])
        #expect(result.estimates.count == 2)
        #expect(result.estimates.filter { $0.budgetID != nil }.count == 1)
        #expect(result.estimates.first { $0.budgetID != nil }?.remaining == 60)
        #expect(result.variableRemaining == 80)
        #expect(result.remaining == 140)
    }

    @Test func deletingOneContoPreservesBudgetsOfItsTransferCounterparty() throws {
        let (container, book, joint, personal, food) = try fixture()
        let context = container.mainContext
        let jointBudget = budget(book, joint, food)
        let personalBudget = budget(book, personal, food)
        let globalBudget = budget(book, nil, food)
        let jointBudgetID = jointBudget.id
        let survivors = Set([personalBudget.id, globalBudget.id])
        for value in [jointBudget, personalBudget, globalBudget] { context.insert(value) }
        let transfer = Transaction(amount: 20, type: .transfer, date: date(10, 5))
        transfer.setFromConto(personal); transfer.setToConto(joint); context.insert(transfer)
        try context.save()
        try FinanceContainerDeletion(context: context).delete(.conto(joint.id))
        let persisted = try ModelContext(container).fetch(FetchDescriptor<Budget>())
        #expect(Set(persisted.map(\.id)) == survivors)
        #expect(!persisted.contains { $0.id == jointBudgetID })
    }

    @Test func sharedContoRoundTripMapsBudgetAndKeepsOtherBudgetsPrivate() throws {
        let (owner, book, joint, personal, food) = try fixture()
        let scoped = budget(book, joint, food)
        let privateBudget = budget(book, personal, food)
        privateBudget.name = "Budget privato"
        owner.mainContext.insert(scoped); owner.mainContext.insert(privateBudget)
        try owner.mainContext.save()
        let scope = try SharedBookOwnerRegistration.register(bookID: book.id, contoID: joint.id, ownerRecordName: "owner", container: owner)
        let snapshot = try SharedBookParticipantExporter.export(scope: scope, container: owner)
        #expect(snapshot.records.filter { $0.id.kind == .budget }.count == 1)
        let payload = String(decoding: try JSONEncoder().encode(snapshot.records), as: UTF8.self)
        #expect(!payload.contains("Budget privato"))
        let target = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        try SharedBookImporter.apply(scope: scope, records: snapshot.records, assets: [:], container: target)
        let context = target.mainContext
        let received = try #require(context.fetch(FetchDescriptor<Budget>()).first)
        let receivedConto = try #require(context.fetch(FetchDescriptor<Conto>()).first)
        #expect(received.contoID == receivedConto.id && received.contoID != joint.id)
        let destination = Account(name: "Libro locale", currency: "EUR")
        context.insert(destination); try context.save()
        try SharedContoPlacement.move(scope: scope, to: destination.id, container: target)
        #expect(received.account?.id == destination.id)
        let returned = try SharedBookParticipantExporter.export(scope: scope, container: target)
        #expect(returned.records == snapshot.records)
        var malicious = snapshot.records
        let index = try #require(malicious.firstIndex { $0.id.kind == .budget })
        malicious[index].fields["scope"] = .text("book")
        malicious[index].fields["conto"] = nil
        #expect(throws: SharedBookImporter.Failure.self) {
            try SharedBookImporter.apply(scope: scope, records: malicious, assets: [:], container: target)
        }
        #expect(received.contoID == receivedConto.id)
    }
}
