import Foundation
import Testing
@testable import FinanceCore

struct SavingsAssessmentTests {
    @Test(arguments: [
        (Decimal(200), Decimal(400), true, SavingsAssessment.inProgress),
        (Decimal(200), Decimal(400), false, SavingsAssessment.belowTarget),
        (Decimal(400), Decimal(400), true, SavingsAssessment.targetReached),
        (Decimal(450), Decimal(400), false, SavingsAssessment.targetReached),
        (Decimal(-80), Decimal(400), true, SavingsAssessment.deficit),
        (Decimal(0), Decimal(0), true, SavingsAssessment.noTarget)
    ])
    func savingsUseExplicitTargetAndPeriodState(_ values: (Decimal, Decimal, Bool, SavingsAssessment)) {
        #expect(SavingsAssessment.compare(actual: values.0, reference: values.1, isCeiling: false, isInProgress: values.2) == values.3)
    }

    @Test(arguments: [
        (Decimal(0), Decimal(0), SavingsAssessment.withinLimit),
        (Decimal(600), Decimal(600), SavingsAssessment.withinLimit),
        (Decimal(650), Decimal(600), SavingsAssessment.limitExceeded),
        (Decimal(-20), Decimal(600), SavingsAssessment.withinLimit)
    ])
    func expenseLimitsHaveTheOppositeDirection(_ values: (Decimal, Decimal, SavingsAssessment)) {
        #expect(SavingsAssessment.compare(actual: values.0, reference: values.1, isCeiling: true, isInProgress: true) == values.2)
    }

    @Test func missingOrInvalidValuesAreNeverRatedAsGood() {
        #expect(SavingsAssessment.compare(actual: nil, reference: 400, isCeiling: false, isInProgress: true) == .unavailable)
        #expect(SavingsAssessment.compare(actual: .nan, reference: 400, isCeiling: false, isInProgress: true) == .unavailable)
        #expect(SavingsAssessment.compare(actual: 50, reference: -1, isCeiling: false, isInProgress: true) == .unavailable)
        #expect(SavingsAssessment.margin(income: 2000, expenses: 1600, invalid: true) == .unavailable)
    }

    @Test func marginWithoutTargetStaysFactual() {
        #expect(SavingsAssessment.margin(income: 2000, expenses: 1600) == .positiveMargin)
        #expect(SavingsAssessment.margin(income: 2000, expenses: 2200) == .deficit)
        #expect(SavingsAssessment.margin(income: 0, expenses: 0) == .balanced)
    }
}
