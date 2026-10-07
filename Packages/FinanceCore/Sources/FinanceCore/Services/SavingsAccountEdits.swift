import Foundation
import SwiftData

@MainActor
public enum SavingsAccountEdits {
    public enum Failure: Error { case invalidGoal, invalidTarget, invalidRate }
    public static func linkGoal(conto: Conto, existingID: UUID?, target: Decimal?, context: ModelContext) throws {
        if let existingID {
            guard let goal = try context.fetch(FetchDescriptor<SavingsGoal>()).first(where: {
                $0.id == existingID && $0.account?.id == conto.account?.id
            }) else { throw Failure.invalidGoal }
            conto.savingsGoalID = goal.id
            if let target {
                guard target > 0 else { throw Failure.invalidTarget }
                goal.targetAmount = target
                goal.updatedAt = Date()
            }
            // Legacy manual progress is retained for unlinking; linked accounts provide the live amount.
            conto.savingsGoal = goal.targetAmount
        } else if let target {
            guard target > 0 else { throw Failure.invalidTarget }
            let goal = SavingsGoal(name: conto.name ?? "Risparmio", targetAmount: target)
            goal.account = conto.account
            context.insert(goal)
            conto.savingsGoalID = goal.id
        } else { conto.savingsGoalID = nil }
    }
}
