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
    
    // MARK: - Default Category Definitions

    public struct DefaultCategoryDefinition: Sendable {
        public let stableKey: String
        public let name: String
        public let color: String
        public let icon: String
    }

    public static let defaultCategoryDefinitions: [DefaultCategoryDefinition] = [
        // Income categories
        .init(stableKey: "stipendio",      name: "Stipendio",       color: "#4CAF50", icon: "dollarsign.circle"),
        .init(stableKey: "freelance",      name: "Freelance",       color: "#8BC34A", icon: "briefcase"),
        .init(stableKey: "investimenti",   name: "Investimenti",    color: "#CDDC39", icon: "chart.line.uptrend.xyaxis"),
        .init(stableKey: "vendite",        name: "Vendite",         color: "#FFC107", icon: "cart"),
        .init(stableKey: "bonus",          name: "Bonus",           color: "#2E7D32", icon: "gift.circle"),
        .init(stableKey: "rimborsi",       name: "Rimborsi",        color: "#388E3C", icon: "arrow.counterclockwise.circle"),

        // Expense categories
        .init(stableKey: "alimentari",     name: "Alimentari",      color: "#F44336", icon: "cart"),
        .init(stableKey: "trasporti",      name: "Trasporti",       color: "#2196F3", icon: "car"),
        .init(stableKey: "casa",           name: "Casa",            color: "#9C27B0", icon: "house"),
        .init(stableKey: "utenze",         name: "Utenze",          color: "#673AB7", icon: "bolt"),
        .init(stableKey: "salute",         name: "Salute",          color: "#E91E63", icon: "cross.case"),
        .init(stableKey: "intrattenimento", name: "Intrattenimento", color: "#FF5722", icon: "gamecontroller"),
        .init(stableKey: "abbigliamento",  name: "Abbigliamento",   color: "#795548", icon: "tshirt"),
        .init(stableKey: "educazione",     name: "Educazione",      color: "#607D8B", icon: "book"),
        .init(stableKey: "regali",         name: "Regali",          color: "#FF4081", icon: "gift"),
        .init(stableKey: "ristoranti",     name: "Ristoranti",      color: "#FF6F00", icon: "fork.knife"),
        .init(stableKey: "viaggi",         name: "Viaggi",          color: "#1976D2", icon: "airplane"),
        .init(stableKey: "sport",          name: "Sport",           color: "#FF9800", icon: "figure.run"),
        .init(stableKey: "tecnologia",     name: "Tecnologia",      color: "#455A64", icon: "iphone"),

        // Generic
        .init(stableKey: "altro",          name: "Altro",           color: "#9E9E9E", icon: "questionmark.circle"),
    ]

    /// Legacy tuple accessor for backward compatibility.
    public static let defaultCategories: [(String, String, String)] =
        defaultCategoryDefinitions.map { ($0.name, $0.color, $0.icon) }
}
