import Foundation
import Testing
@testable import FinanceCore

struct RecordedFlowReportTests {
    let start = Date(timeIntervalSince1970: 10)
    let end = Date(timeIntervalSince1970: 30)
    func entry(_ amount: Decimal, _ type: TransactionType = .expense, category: UUID? = nil,
               time: TimeInterval = 15, valid: Bool = true) -> DirectionTransaction {
        .init(date: Date(timeIntervalSince1970: time), amount: amount, type: type,
              categoryID: category, categoryName: "Senza categoria", isRecurring: false, hasValidAmount: valid)
    }
    func report(_ entries: [DirectionTransaction], categories: [FlowCategory] = []) -> RecordedFlowReport {
        .calculate(transactions: entries, categories: categories,
                   interval: DateInterval(start: start, end: end), now: Date(timeIntervalSince1970: 20))
    }

    @Test func hierarchyConservesDirectAndNestedExpenses() {
        let parent = UUID(), child = UUID(), grandchild = UUID()
        let categories = [FlowCategory(id: parent, name: "Casa", color: "#123456"),
                          FlowCategory(id: child, parentID: parent, name: "Utenze", color: "#123456"),
                          FlowCategory(id: grandchild, parentID: child, name: "Luce", color: "#123456")]
        let value = report([entry(1000, .income), entry(500, category: parent),
                            entry(50, category: child), entry(100, category: grandchild)], categories: categories)
        #expect(value.income == 1000)
        #expect(value.expenses == 650)
        #expect(value.margin == 350)
        #expect(value.categories.count == 1)
        let root = value.categories[0]
        #expect(root.amount == 650)
        #expect(root.children.reduce(Decimal.zero) { $0 + $1.amount } == root.amount)
        #expect(root.children.first(where: { $0.id.hasSuffix(":direct") })?.amount == 500)
        let utilities = root.children.first { $0.categoryID == child }!
        #expect(utilities.children.reduce(Decimal.zero) { $0 + $1.amount } == utilities.amount)
    }

    @Test func filteringAndDeficitStayFactual() {
        let value = report([entry(100, .income), entry(250), entry(900, .transfer),
                            entry(800, .income, time: 9), entry(700, time: 21), entry(600, time: 30)])
        #expect(value.income == 100)
        #expect(value.expenses == 250)
        #expect(value.margin == 0)
        #expect(value.shortfall == 150)
        #expect(value.canDraw)
        #expect(report([entry(50)]).shortfall == 50)
        #expect(report([entry(100, .income)]).margin == 100)
    }

    @Test func missingParentsAndCyclesDoNotLoseHistory() {
        let a = UUID(), b = UUID(), orphan = UUID()
        let categories = [FlowCategory(id: a, parentID: b, name: "A", color: "#123456"),
                          FlowCategory(id: b, parentID: a, name: "B", color: "#123456"),
                          FlowCategory(id: orphan, parentID: UUID(), name: "Orfana", color: "#123456")]
        let value = report([entry(10, category: a), entry(20, category: b), entry(30, category: orphan),
                            entry(40), entry(50, category: UUID())], categories: categories)
        #expect(value.categories.reduce(Decimal.zero) { $0 + $1.amount } == 150)
        #expect(value.categories.count == 5)
    }

    @Test func correctionsNetWithinCategoryAndNegativeBranchesAreExplicit() {
        let a = UUID(), b = UUID()
        let positive = report([entry(100, category: a), entry(-20, category: a)])
        #expect(positive.expenses == 80)
        #expect(positive.categories[0].amount == 80)
        #expect(positive.canDraw)
        let negative = report([entry(100, category: a), entry(-20, category: b)])
        #expect(negative.expenses == 80)
        #expect(negative.hasNegativeBranches)
        #expect(!negative.canDraw)
        #expect(!report([entry(-20, .income)]).canDraw)
    }

    @Test func invalidValuesDoNotProduceMisleadingDiagram() {
        #expect(!report([entry(.nan)]).canDraw)
        #expect(!report([entry(0, valid: false)]).canDraw)
        #expect(report([entry(.nan, .transfer), entry(.nan, time: 25)]).canDraw)
        #expect(report([]).categories.isEmpty)
    }
}
