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
    public var kindRaw: String?
    
    public var account: Account?
    
    @Relationship(deleteRule: .nullify, inverse: \Transaction.category)
    public var transactions: [Transaction]?

    /// Direct many-to-many relationship with Budget
    @Relationship(deleteRule: .nullify, inverse: \Budget.categories)
    public var budgets: [Budget]?

    public init(
        name: String,
        color: String = CategoryPalette.fallback,
        icon: String = "tag",
        parentCategoryId: UUID? = nil,
        kind: CategoryKind? = nil
    ) {
        self.name = name
        self.color = color
        self.icon = icon
        self.parentCategoryId = parentCategoryId
        self.kindRaw = kind?.rawValue
        self.createdAt = Date()
        self.updatedAt = Date()
        self.isActive = true
        self.transactions = []
        self.budgets = []
    }

    public var isSubcategory: Bool {
        parentCategoryId != nil
    }

    /// Income or expense; `nil` means the category fits both (legacy and generic ones).
    public var kind: CategoryKind? {
        get { kindRaw.flatMap(CategoryKind.init(rawValue:)) }
        set { kindRaw = newValue?.rawValue }
    }

    /// Whether the category can classify a transaction of the given type.
    public func fits(_ type: TransactionType) -> Bool {
        guard let kind else { return type != .transfer }
        return kind.transactionType == type
    }

    // MARK: - Default Category Definitions

    public struct DefaultCategoryDefinition: Sendable {
        public let stableKey: String
        public let name: String
        public let color: String
        public let icon: String
        public let kind: CategoryKind?
        /// Stable key of the macro category; `nil` for a macro category.
        public let parentKey: String?
    }

    private struct Macro {
        let key: String, name: String, color: String, icon: String, kind: CategoryKind?
        let children: [(key: String, name: String, icon: String)]
    }

    // Keys from the earlier flat list are reused so existing books can be upgraded in place.
    private static let defaultTree: [Macro] = [
        // Income
        Macro(key: "lavoro", name: "Lavoro", color: CategoryPalette.ottanio, icon: "briefcase", kind: .income, children: [
            ("stipendio", "Stipendio", "dollarsign.circle"),
            ("freelance", "Freelance", "laptopcomputer"),
            ("bonus", "Bonus", "gift.circle"),
        ]),
        Macro(key: "rendite", name: "Rendite", color: CategoryPalette.oliva, icon: "chart.line.uptrend.xyaxis", kind: .income, children: [
            ("investimenti", "Investimenti", "chart.pie"),
            ("interessi", "Interessi", "percent"),
        ]),
        Macro(key: "altre-entrate", name: "Altre entrate", color: CategoryPalette.salvia, icon: "plus.circle", kind: .income, children: [
            ("rimborsi", "Rimborsi", "arrow.counterclockwise.circle"),
            ("vendite", "Vendite", "tag"),
            ("regali-ricevuti", "Regali ricevuti", "gift"),
        ]),

        // Expense
        Macro(key: "casa", name: "Casa", color: CategoryPalette.prugna, icon: "house", kind: .expense, children: [
            ("affitto", "Affitto o mutuo", "key"),
            ("utenze", "Utenze", "bolt"),
            ("manutenzione", "Manutenzione", "hammer"),
            ("arredamento", "Arredamento", "sofa"),
        ]),
        Macro(key: "cibo", name: "Cibo", color: CategoryPalette.terracotta, icon: "fork.knife", kind: .expense, children: [
            ("alimentari", "Alimentari", "cart"),
            ("ristoranti", "Ristoranti", "fork.knife.circle"),
            ("bar", "Bar e caffè", "cup.and.saucer"),
            ("consegne", "Consegne a domicilio", "takeoutbag.and.cup.and.straw"),
        ]),
        Macro(key: "trasporti", name: "Trasporti", color: CategoryPalette.petrolio, icon: "car", kind: .expense, children: [
            ("carburante", "Carburante", "fuelpump"),
            ("mezzi-pubblici", "Mezzi pubblici", "tram"),
            ("auto", "Auto e manutenzione", "wrench.and.screwdriver"),
            ("parcheggi", "Parcheggi e pedaggi", "parkingsign"),
        ]),
        Macro(key: "salute", name: "Salute", color: CategoryPalette.rosaAntico, icon: "cross.case", kind: .expense, children: [
            ("farmacia", "Farmacia", "pills"),
            ("visite", "Visite mediche", "stethoscope"),
            ("cura-personale", "Cura personale", "scissors"),
        ]),
        Macro(key: "tempo-libero", name: "Tempo libero", color: CategoryPalette.albicocca, icon: "ticket", kind: .expense, children: [
            ("intrattenimento", "Intrattenimento", "gamecontroller"),
            ("abbonamenti", "Abbonamenti", "play.tv"),
            ("sport", "Sport", "figure.run"),
            ("hobby", "Hobby", "paintpalette"),
        ]),
        Macro(key: "shopping", name: "Shopping", color: CategoryPalette.ocra, icon: "bag", kind: .expense, children: [
            ("abbigliamento", "Abbigliamento", "tshirt"),
            ("tecnologia", "Tecnologia", "iphone"),
            ("regali", "Regali", "gift"),
        ]),
        Macro(key: "viaggi", name: "Viaggi", color: CategoryPalette.indaco, icon: "airplane", kind: .expense, children: [
            ("trasporti-viaggio", "Voli e treni", "airplane.departure"),
            ("alloggi", "Alloggi", "bed.double"),
            ("escursioni", "Escursioni e attività", "map"),
        ]),
        Macro(key: "educazione", name: "Educazione", color: CategoryPalette.malva, icon: "book", kind: .expense, children: [
            ("corsi", "Corsi", "graduationcap"),
            ("libri", "Libri", "books.vertical"),
        ]),
        Macro(key: "famiglia", name: "Famiglia", color: CategoryPalette.cuoio, icon: "figure.2.and.child.holdinghands", kind: .expense, children: [
            ("figli", "Figli", "figure.and.child.holdinghands"),
            ("animali", "Animali domestici", "pawprint"),
        ]),
        Macro(key: "tasse-finanza", name: "Tasse e finanza", color: CategoryPalette.ardesia, icon: "building.columns", kind: .expense, children: [
            ("tasse", "Tasse", "doc.text"),
            ("commissioni", "Commissioni bancarie", "creditcard"),
            ("assicurazioni", "Assicurazioni", "checkmark.shield"),
        ]),

        // Generic
        Macro(key: "altro", name: "Altro", color: CategoryPalette.tortora, icon: "questionmark.circle", kind: nil, children: []),
    ]

    /// Macro categories first, each followed by its subcategories. Subcategories share the macro's colour.
    public static let defaultCategoryDefinitions: [DefaultCategoryDefinition] = defaultTree.flatMap { macro in
        [DefaultCategoryDefinition(stableKey: macro.key, name: macro.name, color: macro.color,
                                   icon: macro.icon, kind: macro.kind, parentKey: nil)]
        + macro.children.map {
            DefaultCategoryDefinition(stableKey: $0.key, name: $0.name, color: macro.color,
                                      icon: $0.icon, kind: macro.kind, parentKey: macro.key)
        }
    }

    /// Legacy tuple accessor for backward compatibility.
    public static let defaultCategories: [(String, String, String)] =
        defaultCategoryDefinitions.map { ($0.name, $0.color, $0.icon) }
}

public enum CategoryKind: String, Codable, CaseIterable, Sendable {
    case income
    case expense

    public var transactionType: TransactionType { self == .income ? .income : .expense }

    public init?(_ type: TransactionType) {
        switch type {
        case .income: self = .income
        case .expense: self = .expense
        case .transfer: return nil
        }
    }

    public var displayName: String { self == .income ? "Entrate" : "Spese" }
}
