import Foundation
import SwiftData

@Model
public final class Category {
    public var id: UUID = UUID()
    public var externalID: String = UUID().uuidString
    public var name: String?
    public var color: String?
    public var icon: String?
    public var createdAt: Date?
    public var updatedAt: Date?
    public var isActive: Bool?
    public var parentCategoryId: UUID?
    
    public var account: Account?
    
    @Relationship(deleteRule: .nullify, inverse: \Transaction.category)
    public var transactions: [Transaction]?

    /// Direct many-to-many relationship with Budget
    @Relationship(deleteRule: .nullify, inverse: \Budget.categories)
    public var budgets: [Budget]?

    public init(
        name: String,
        color: String = "#007AFF",
        icon: String = "tag",
        parentCategoryId: UUID? = nil
    ) {
        self.name = name
        self.color = color
        self.icon = icon
        self.parentCategoryId = parentCategoryId
        self.createdAt = Date()
        self.updatedAt = Date()
        self.isActive = true
        self.transactions = []
        self.budgets = []
    }

    public var isSubcategory: Bool {
        parentCategoryId != nil
    }
    
    public static let defaultCategories = [
        // Income categories
        ("Stipendio", "#4CAF50", "dollarsign.circle"),
        ("Freelance", "#8BC34A", "briefcase"),
        ("Investimenti", "#CDDC39", "chart.line.uptrend.xyaxis"),
        ("Vendite", "#FFC107", "cart"),
        ("Bonus", "#2E7D32", "gift.circle"),
        ("Rimborsi", "#388E3C", "arrow.counterclockwise.circle"),
        
        // Expense categories  
        ("Alimentari", "#F44336", "cart"),
        ("Trasporti", "#2196F3", "car"),
        ("Casa", "#9C27B0", "house"),
        ("Utenze", "#673AB7", "bolt"),
        ("Salute", "#E91E63", "cross.case"),
        ("Intrattenimento", "#FF5722", "gamecontroller"),
        ("Abbigliamento", "#795548", "tshirt"),
        ("Educazione", "#607D8B", "book"),
        ("Regali", "#FF4081", "gift"),
        ("Ristoranti", "#FF6F00", "fork.knife"),
        ("Viaggi", "#1976D2", "airplane"),
        ("Sport", "#FF9800", "figure.run"),
        ("Tecnologia", "#455A64", "iphone"),
        
        // Generic
        ("Altro", "#9E9E9E", "questionmark.circle")
    ]
}
