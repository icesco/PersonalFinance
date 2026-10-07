import Foundation
import Testing
@testable import FinanceCore

struct RecurrenceFrequencyTests {
    @Test func monthlyEquivalentNormalizesEveryFrequency() {
        #expect(RecurrenceFrequency.monthly.monthlyEquivalent(of: 10) == 10)
        #expect(RecurrenceFrequency.yearly.monthlyEquivalent(of: 120) == 10)
        #expect(RecurrenceFrequency.quarterly.monthlyEquivalent(of: 30) == 10)
        #expect(RecurrenceFrequency.semiannually.monthlyEquivalent(of: 60) == 10)
        #expect(RecurrenceFrequency.weekly.monthlyEquivalent(of: 3) == 13)
        #expect(RecurrenceFrequency.biweekly.monthlyEquivalent(of: 6) == 13)
        #expect(RecurrenceFrequency.daily.monthlyEquivalent(of: 12) == 365)
    }
}
