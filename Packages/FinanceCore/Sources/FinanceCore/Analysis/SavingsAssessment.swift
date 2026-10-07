import Foundation

/// Judges a recorded value against an explicit user reference, not a universal savings threshold.
public enum SavingsAssessment: String, Sendable, Equatable {
    case unavailable, deficit, positiveMargin, balanced
    case withinLimit, limitExceeded, targetReached, inProgress, belowTarget, noTarget

    public static func margin(income: Decimal, expenses: Decimal, invalid: Bool = false) -> Self {
        guard !invalid, !income.isNaN, !expenses.isNaN else { return .unavailable }
        if expenses > income { return .deficit }
        if income == expenses { return .balanced }
        return .positiveMargin
    }

    public static func compare(actual: Decimal?, reference: Decimal, isCeiling: Bool, isInProgress: Bool) -> Self {
        guard let actual, !actual.isNaN, !reference.isNaN, reference >= 0 else { return .unavailable }
        if isCeiling { return actual > reference ? .limitExceeded : .withinLimit }
        if actual < 0 { return .deficit }
        if reference == 0 { return .noTarget }
        if actual >= reference { return .targetReached }
        return isInProgress ? .inProgress : .belowTarget
    }
}
