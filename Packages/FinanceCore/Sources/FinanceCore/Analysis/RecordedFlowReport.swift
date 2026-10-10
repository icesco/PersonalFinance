import Foundation

/// Value-only category metadata, including archived categories for historical reports.
public struct FlowCategory: Sendable {
    public let id: UUID
    public let parentID: UUID?
    public let name: String
    public let color: String

    public init(id: UUID, parentID: UUID? = nil, name: String, color: String) {
        self.id = id
        self.parentID = parentID
        self.name = name
        self.color = color
    }
}

public struct RecordedFlowNode: Identifiable, Sendable {
    public let id: String
    public let categoryID: UUID?
    public let name: String
    public let color: String
    public let amount: Decimal
    public let children: [Self]
}

/// Net recorded flows in one currency. A residual is margin, not measured savings.
public struct RecordedFlowReport: Sendable {
    public let income: Decimal
    public let expenses: Decimal
    public let categories: [RecordedFlowNode]
    public let hasInvalidAmounts: Bool
    public let hasNegativeBranches: Bool
    public var margin: Decimal { max(0, income - expenses) }
    public var shortfall: Decimal { max(0, expenses - income) }
    public var canDraw: Bool { !hasInvalidAmounts && !hasNegativeBranches }

    public static func calculate(transactions: [DirectionTransaction], categories: [FlowCategory],
                                 interval: DateInterval, now: Date = Date()) -> Self {
        let metadata = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var own: [String: Decimal] = [:]
        var names: [String: String] = [:]
        var ids: [String: UUID] = [:]
        var income: Decimal = 0
        var expenses: Decimal = 0
        var invalid = false
        for entry in transactions where entry.date >= interval.start && entry.date < interval.end && entry.date <= now {
            guard entry.type != .transfer else { continue }
            guard entry.hasValidAmount, !entry.amount.isNaN else { invalid = true; continue }
            if entry.type == .income { income += entry.amount; continue }
            expenses += entry.amount
            let key = entry.categoryID?.uuidString ?? "uncategorized"
            own[key, default: 0] += entry.amount
            names[key] = entry.categoryID.flatMap { metadata[$0]?.name } ?? entry.categoryName
            ids[key] = entry.categoryID
        }
        // Resolve ancestry defensively: malformed cycles become standalone branches.
        func ancestry(_ id: UUID) -> [UUID] {
            var path = [id]
            var seen: Set<UUID> = [id]
            var cursor = id
            while let parent = metadata[cursor]?.parentID, metadata[parent] != nil {
                guard seen.insert(parent).inserted else { return [id] }
                path.append(parent)
                cursor = parent
            }
            return path.reversed()
        }
        var children: [String: Set<String>] = [:]
        var roots: Set<String> = []
        for key in own.keys {
            let path = ids[key].map { ancestry($0).map(\.uuidString) } ?? [key]
            if let root = path.first { roots.insert(root) }
            for (parent, child) in zip(path, path.dropFirst()) { children[parent, default: []].insert(child) }
        }
        func sorted(_ nodes: [RecordedFlowNode]) -> [RecordedFlowNode] {
            nodes.sorted { $0.amount == $1.amount ? $0.id < $1.id : $0.amount > $1.amount }
        }
        func node(_ key: String) -> RecordedFlowNode {
            let category = UUID(uuidString: key).flatMap { metadata[$0] }
            var branches = (children[key] ?? []).map(node)
            let direct = own[key] ?? 0
            // Preserve expenses assigned directly to a parent alongside its children.
            if !branches.isEmpty, direct != 0 {
                branches.append(.init(id: key + ":direct", categoryID: category?.id,
                                      name: "Direttamente nella categoria", color: category?.color ?? "#888888",
                                      amount: direct, children: []))
            }
            let amount = branches.isEmpty ? direct : branches.reduce(Decimal.zero) { $0 + $1.amount }
            return .init(id: key, categoryID: UUID(uuidString: key),
                         name: category?.name ?? (names[key].flatMap { $0.isEmpty ? nil : $0 } ?? "Da classificare"),
                         color: category?.color ?? "#888888", amount: amount,
                         children: sorted(branches.filter { $0.amount != 0 }))
        }
        let nodes = sorted(roots.map(node))
        func negative(_ node: RecordedFlowNode) -> Bool {
            node.amount < 0 || node.children.contains(where: negative)
        }
        return .init(income: income, expenses: expenses, categories: nodes.filter { $0.amount > 0 },
                     hasInvalidAmounts: invalid || income.isNaN || expenses.isNaN,
                     hasNegativeBranches: income < 0 || expenses < 0 || nodes.contains(where: negative))
    }
}
