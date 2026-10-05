import Testing
import Foundation
@testable import FinanceCore

struct AmountCalculatorTests {
    @Test func decimalArithmeticAndPrecedence() throws {
        #expect(try AmountCalculator.evaluate("0,1 + 0,2") == Decimal(string: "0.3"))
        #expect(try AmountCalculator.evaluate("12,50 + 8 × 2") == Decimal(string: "28.5"))
        #expect(try AmountCalculator.evaluate("(12.50 + 8) ÷ 2") == Decimal(string: "10.25"))
        #expect(try AmountCalculator.evaluate("-5 + 2 × -3") == -11)
        #expect(try AmountCalculator.evaluate("20 - 5 - 3") == 12)
    }
    @Test func rejectsInvalidInputs() {
        for input in ["", "1+", "1,2,3", "(1+2", "2abc", "1..2", "2(3)"] {
            #expect(throws: AmountCalculator.Failure.invalidExpression) { try AmountCalculator.evaluate(input) }
        }
        #expect(throws: AmountCalculator.Failure.divisionByZero) { try AmountCalculator.evaluate("2/(3-3)") }
        #expect(throws: AmountCalculator.Failure.outOfRange) { try AmountCalculator.evaluate(String(repeating: "1", count: 129)) }
    }
}
