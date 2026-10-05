import Foundation
import Testing
@testable import FinanceCore

struct BalanceInputTests {
    @Test func acceptsZeroSignedAndDecimalBalances() {
        #expect(BalanceInput.parse("", currency: "EUR") == 0)
        #expect(BalanceInput.parse(" -125,50 ", currency: "EUR") == Decimal(string: "-125.50"))
        #expect(BalanceInput.parse("+12.50", currency: "USD") == Decimal(string: "12.50"))
        #expect(BalanceInput.parse(".50", currency: "EUR") == Decimal(string: "0.50"))
        #expect(BalanceInput.parse("12", currency: "JPY") == 12)
    }
    @Test func rejectsPartialParsingGroupingAndUnsupportedPrecision() {
        for input in ["12abc", "1.234,56", "1,234.56", "1 234", "NaN", "inf", "1e3", "--12", "12,", "-", "1+2", String(repeating: "9", count: 29)] {
            #expect(BalanceInput.parse(input, currency: "EUR") == nil)
        }
        #expect(BalanceInput.parse("1.234", currency: "EUR") == nil)
        #expect(BalanceInput.parse("1.20", currency: "JPY") == nil)
        #expect(BalanceInput.parse("1.234", currency: "KWD") == Decimal(string: "1.234"))
    }
}
