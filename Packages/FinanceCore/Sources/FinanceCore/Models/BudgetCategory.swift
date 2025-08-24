import Foundation
import SwiftData

@Model
public final class BudgetCategory {
    public var id: UUID = UUID()
    public var externalID: String = UUID().uuidString
    public var createdAt: Date?
    
    public var budget: Budget?
    public var category: Category?
    
    public init(budget: Budget, category: Category) {
        // id and externalID now have default values
        self.createdAt = Date()
        self.budget = budget
        self.category = category
    }
}
