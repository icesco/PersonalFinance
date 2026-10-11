import Foundation
import Testing
@testable import FinanceCore

struct MarginScenarioTests {
    @Test func outcomesPreserveSignedAmountsAndCents() {
        let remaining = MarginScenario(margin: Decimal(string: "720.25")!, expense: 300)
        #expect(remaining?.remaining == Decimal(string: "420.25"))
        #expect(remaining?.outcome == .remaining)
        #expect(MarginScenario(margin: 300, expense: 300)?.outcome == .exhausted)
        #expect(MarginScenario(margin: 200, expense: 300)?.remaining == -100)
        #expect(MarginScenario(margin: -50, expense: 300)?.remaining == -350)
        #expect(MarginScenario(margin: -50, expense: 300)?.outcome == .shortfall)
        #expect(MarginScenario(margin: 720, expense: 0)?.remaining == 720)
    }

    @Test func invalidInputsCannotProduceAProjection() {
        #expect(MarginScenario(margin: .nan, expense: 300) == nil)
        #expect(MarginScenario(margin: 300, expense: .nan) == nil)
        #expect(MarginScenario(margin: 300, expense: -1) == nil)
        #expect(MarginScenario(margin: -Decimal.greatestFiniteMagnitude,
                               expense: Decimal.greatestFiniteMagnitude) == nil)
        for text in ["", " ", "-10", "1.000,50", "1,2,3", "300 euro", ".", "NaN"] {
            #expect(MarginScenario.expense(from: text) == nil)
        }
        #expect(MarginScenario.expense(from: " 300,50 ") == Decimal(string: "300.50"))
        #expect(MarginScenario.expense(from: "300.50") == Decimal(string: "300.50"))
        #expect(MarginScenario.expense(from: "0") == 0)
    }

    @Test func displayedAmountsDoNotProduceASubCentShortfall() {
        #expect(MarginScenario(margin: Decimal(string: "2185.227272")!, expense: Decimal(string: "2185.23")!)?.outcome == .exhausted)
        #expect(MarginScenario(margin: Decimal(string: "720.25")!, expense: 300, currency: "JPY")?.remaining == 420)
        #expect(MarginScenario(margin: Decimal(string: "1.234")!, expense: Decimal(string: "0.005")!, currency: "KWD")?.remaining == Decimal(string: "1.229"))
    }
}
