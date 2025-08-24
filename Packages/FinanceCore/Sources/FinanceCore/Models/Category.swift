import Foundation
import SwiftData

public enum CategoryType: String, CaseIterable, Codable {
    case income = "income"
    case expense = "expense"
    
    public var displayName: String {
        switch self {
        case .income: return "Entrata"
        case .expense: return "Spesa"
        }
    }
}

@Model
public final class Category {
    public var id: UUID = UUID()
    public var externalID: String = UUID().uuidString
    public var name: String?
    public var type: CategoryType?
    public var color: String?
    public var icon: String?
    public var createdAt: Date?
    public var updatedAt: Date?
    public var isActive: Bool?
    public var parentCategoryId: UUID?
    
    public var account: Account?
    
    @Relationship(deleteRule: .nullify, inverse: \Transaction.category)
    public var transactions: [Transaction]?
    
    @Relationship(deleteRule: .cascade, inverse: \BudgetCategory.category)
    public var budgetCategories: [BudgetCategory]?
    
    public init(
        name: String,
        type: CategoryType,
        color: String = "#007AFF",
        icon: String = "tag",
        parentCategoryId: UUID? = nil
    ) {
        // id and externalID now have default values
        self.name = name
        self.type = type
        self.color = color
        self.icon = icon
        self.parentCategoryId = parentCategoryId
        self.createdAt = Date()
        self.updatedAt = Date()
        self.isActive = true
        self.transactions = []
        self.budgetCategories = []
    }
    
    public var isSubcategory: Bool {
        parentCategoryId != nil
    }
    
    public var budgets: [Budget] {
        (budgetCategories ?? []).compactMap { $0.budget }
    }
    
    public static let defaultIncomeCategories = [
        ("Stipendio", "#4CAF50", "dollarsign.circle"),
        ("Freelance", "#8BC34A", "briefcase"),
        ("Investimenti", "#CDDC39", "chart.line.uptrend.xyaxis"),
        ("Vendite", "#FFC107", "cart"),
        ("Altro", "#FF9800", "questionmark.circle")
    ]
    
    public static let defaultExpenseCategories = [
        ("Alimentari", "#F44336", "cart"),
        ("Trasporti", "#2196F3", "car"),
        ("Casa", "#9C27B0", "house"),
        ("Utenze", "#673AB7", "bolt"),
        ("Salute", "#E91E63", "cross.case"),
        ("Intrattenimento", "#FF5722", "gamecontroller"),
        ("Abbigliamento", "#795548", "tshirt"),
        ("Educazione", "#607D8B", "book"),
        ("Regali", "#FF4081", "gift"),
        ("Altro", "#9E9E9E", "questionmark.circle")
    ]
}
