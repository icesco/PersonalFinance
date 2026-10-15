import Foundation
import Testing
@testable import FinanceCore

struct SavingsValuationSeriesTests {
    @Test func seriesMatchesIndependentValuationsExactly() throws {
        for zone in ["UTC", "Europe/Rome", "Pacific/Kiritimati"] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try #require(TimeZone(identifier: zone))
            let start = try #require(calendar.date(from: DateComponents(year: 2023, month: 11, day: 20)))
            let movements: [SavingsMovement] = (0..<180).map { index in
                let offset = Double(index / 3 - 5) * 9 * 86_400
                return SavingsMovement(date: start.addingTimeInterval(offset),
                    amount: Decimal(index % 11 - 5) / 7, isInterest: index % 3 != 0)
            }
            let rates: [SavingsRate] = (0..<9).map { index in
                SavingsRate(effectiveDate: start.addingTimeInterval(Double(index - 1) * 50 * 86_400),
                    annualPercent: Decimal(index % 5 - 2) / 3)
            }
            var dates = (-60...600).map { start.addingTimeInterval(Double($0) * 86_400 + 1_234) }
            dates += movements.map(\.date) + rates.map(\.effectiveDate) + [start, start, start.addingTimeInterval(-1)]
            dates.reverse()
            for schedule in [rates, [], rates + [rates[2]]] {
                let actual = SavingsValuation.values(initialBalance: 1_000, start: start, rates: schedule,
                    movements: movements, at: dates, calendar: calendar)
                let expected = dates.map { SavingsValuation.value(initialBalance: 1_000, start: start,
                    rates: schedule, movements: movements, at: $0, calendar: calendar) }
                #expect(actual == expected)
            }
        }
    }

    @Test func samplesDoNotChangeLaterDecimalRounding() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let movements = [SavingsMovement(date: start.addingTimeInterval(1_234_567), amount: Decimal(17) / 13)]
        let rates = [SavingsRate(effectiveDate: start, annualPercent: Decimal(7) / 11)]
        let dates = (0..<400).map { start.addingTimeInterval(Double($0) * 86_400 + 123) }
        let full = SavingsValuation.values(initialBalance: Decimal(10_000) / 3, start: start,
            rates: rates, movements: movements, at: dates)
        let sparseDates = dates.enumerated().filter { $0.offset % 17 == 0 }.map(\.element)
        let sparse = SavingsValuation.values(initialBalance: Decimal(10_000) / 3, start: start,
            rates: rates, movements: movements, at: sparseDates)
        #expect(sparse == full.enumerated().filter { $0.offset % 17 == 0 }.map(\.element))
        #expect(SavingsValuation.values(initialBalance: 1, start: start, rates: rates,
            movements: movements, at: []).isEmpty)
    }
}
