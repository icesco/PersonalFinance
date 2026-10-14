import Foundation
import Testing
@testable import FinanceCore

struct MonthlySafetyMarginTests {
    @Test func percentageUsesRemainingAndFixedReserveIsSeparate() throws {
        let percent = try #require(MonthlySafetyMargin(necessary: 90, mode: .percentage, value: 10, currency: "EUR"))
        #expect(percent.reserve == 9)
        #expect(percent.requiredWithReserve == 99)
        let fixed = try #require(MonthlySafetyMargin(necessary: 90, mode: .fixed, value: 100, currency: "EUR"))
        #expect(fixed.reserve == 100)
        #expect(fixed.requiredWithReserve == 190)
        #expect(fixed.shortfall(minimumBalance: 249, endingBalance: 174, variableRemaining: 15) == 0)
    }
    @Test func missingEstimateCannotBecomeFalseFullTotal() throws {
        let percent = try #require(MonthlySafetyMargin(necessary: nil, mode: .percentage, value: 10, currency: "EUR"))
        #expect(percent.reserve == nil)
        #expect(percent.requiredWithReserve == nil)
        let fixed = try #require(MonthlySafetyMargin(necessary: nil, mode: .fixed, value: 100, currency: "EUR"))
        #expect(fixed.reserve == 100)
        #expect(fixed.requiredWithReserve == nil)
        #expect(fixed.shortfall(minimumBalance: 10, endingBalance: 10, variableRemaining: nil) == nil)
        #expect(fixed.shortfall(minimumBalance: nil, endingBalance: nil, variableRemaining: 30) == nil)
    }
    @Test func reserveSurvivesEarlyDeadlinesAndVariableSpending() throws {
        let reserve = try #require(MonthlySafetyMargin(necessary: 200, mode: .fixed, value: 100, currency: "EUR"))
        #expect(reserve.shortfall(minimumBalance: 40, endingBalance: 500, variableRemaining: 50) == 60)
        #expect(reserve.shortfall(minimumBalance: -40, endingBalance: 500, variableRemaining: 50) == 140)
        #expect(reserve.shortfall(minimumBalance: 150, endingBalance: 150, variableRemaining: 80) == 30)
        #expect(reserve.shortfall(minimumBalance: 200, endingBalance: 200, variableRemaining: 80) == 0)
    }
    @Test func zeroAndInvalidInputsAndCurrencyRounding() throws {
        let zero = try #require(MonthlySafetyMargin(necessary: 90, mode: .percentage, value: 0, currency: "EUR"))
        #expect(zero.reserve == 0)
        #expect(zero.requiredWithReserve == 90)
        #expect(MonthlySafetyMargin(necessary: 90, mode: .fixed, value: -1, currency: "EUR") == nil)
        #expect(MonthlySafetyMargin(necessary: .nan, mode: .fixed, value: 1, currency: "EUR") == nil)
        #expect(MonthlySafetyMargin(necessary: 90, mode: .percentage, value: .nan, currency: "EUR") == nil)
        #expect(MonthlySafetyMargin(necessary: 99.95, mode: .percentage, value: 12.5, currency: "EUR")?.reserve == 12.49)
        #expect(MonthlySafetyMargin(necessary: 90, mode: .fixed, value: 100.6, currency: "JPY")?.reserve == 101)
    }
}
