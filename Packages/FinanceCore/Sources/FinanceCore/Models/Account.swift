import Foundation
import SwiftData

@Model
public final class Account {
    public var id: UUID = UUID()
    public var externalID: String = UUID().uuidString
    public var name: String?
    public var currency: String?
    public var createdAt: Date?
    public var updatedAt: Date?
    public var isActive: Bool?
    /// Versioned, portable plan; nil means the user has not made a choice yet.
    public var budgetingPlanJSON: String?
    
    @Relationship(deleteRule: .cascade, inverse: \Conto.account)
    public var conti: [Conto]?
    
    @Relationship(deleteRule: .cascade, inverse: \Category.account)
    public var categories: [Category]?
    
    @Relationship(deleteRule: .cascade, inverse: \Budget.account)
    public var budgets: [Budget]?
    
    @Relationship(deleteRule: .cascade, inverse: \SavingsGoal.account)
    public var savingsGoals: [SavingsGoal]?

    public init(
        name: String,
        currency: String = "EUR"
    ) {
        self.name = name
        self.currency = currency
        self.createdAt = Date()
        self.updatedAt = Date()
        self.isActive = true
        self.conti = []
        self.categories = []
        self.budgets = []
        self.savingsGoals = []
    }
    
    public var totalBalance: Decimal {
        (conti ?? []).reduce(0) { $0 + $1.balance }
    }
    
    public var activeConti: [Conto] {
        (conti ?? []).filter { $0.isActive == true }
    }
}
