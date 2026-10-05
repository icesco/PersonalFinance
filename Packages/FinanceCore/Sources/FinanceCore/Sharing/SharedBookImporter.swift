import Foundation
import SwiftData
import CryptoKit

/// Applies a complete, reconciled book snapshot, never an incremental page of
/// CloudKit results. Call the merge layer before this to preserve local edits.
@MainActor
public enum SharedBookImporter {
    public enum Failure: Error { case invalidGraph, invalidField(String), identityCollision, protectedTransfer, invalidAsset, unreconciledDeletion }

    @discardableResult
    public static func apply(scope: SharedBookScope, records: [SharedBookRecord], assets: [SharedRecordID: Data],
                             container: ModelContainer) throws -> UUID {
        let graph = try validate(scope: scope, records: records, assets: assets)
        let rootID = SharedRecordID(bookID: scope.bookID, kind: .book, entityID: scope.bookID.uuidString.lowercased())
        guard let root = graph[rootID] else { throw Failure.invalidGraph }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        do {
            let scopeKey = scope.key
            let memberships = try context.fetch(FetchDescriptor<SharedBookMembership>(predicate: #Predicate { $0.scopeKey == scopeKey }))
            let links = try context.fetch(FetchDescriptor<SharedBookRecordLink>(predicate: #Predicate { $0.scopeKey == scopeKey }))
            var aliases: [String: String] = [:]
            for link in links {
                if let existing = aliases[link.remoteRecordName], existing != link.localIdentity { throw Failure.identityCollision }
                aliases[link.remoteRecordName] = link.localIdentity
            }
            let departures = try context.fetch(FetchDescriptor<SharedBookDeparture>(predicate: #Predicate { $0.scopeKey == scopeKey }))
            let namespace = memberships.first?.importNamespace ?? (memberships.isEmpty ? scope.importNamespace(afterLeaving: Set(departures.map(\.localBookID))) : nil)
            let identityScope = namespace.map { SharedBookScope(ownerName: scope.ownerName, bookID: $0) } ?? scope
            let localBookID = memberships.first?.localBookID ?? identityScope.isolatedID(for: rootID)
            guard memberships.allSatisfy({ $0.localBookID == localBookID && $0.ownerName == scope.ownerName && $0.remoteBookID == scope.bookID && $0.importNamespace == namespace }),
                  aliases[rootID.recordName] == nil || aliases[rootID.recordName] == localBookID.uuidString.lowercased() else { throw Failure.identityCollision }
            var ids: [SharedRecordID: UUID] = [:]
            for record in records where record.id.kind != .recurrence {
                let proposed = record.id == rootID ? localBookID : identityScope.isolatedID(for: record.id)
                guard let uuid = aliases[record.id.recordName].flatMap(UUID.init(uuidString:)) ?? (aliases[record.id.recordName] == nil ? proposed : nil) else { throw Failure.identityCollision }
                ids[record.id] = uuid
            }
            func localID(_ reference: SharedRecordID?) throws -> UUID? {
                guard let reference else { return nil }
                guard let value = ids[reference] else { throw Failure.invalidGraph }
                return value
            }
            func register(_ record: SharedBookRecord, localIdentity: String) throws {
                if let existing = aliases[record.id.recordName] {
                    guard existing == localIdentity else { throw Failure.identityCollision }
                } else {
                    context.insert(SharedBookRecordLink(scopeKey: scopeKey, remoteRecordName: record.id.recordName, localIdentity: localIdentity))
                    aliases[record.id.recordName] = localIdentity
                }
            }
            var books = try indexed(context.fetch(FetchDescriptor<Account>()), key: \.id)
            var conti = try indexed(context.fetch(FetchDescriptor<Conto>()), key: \.id)
            var categories = try indexed(context.fetch(FetchDescriptor<Category>()), key: \.id)
            var transactions = try indexed(context.fetch(FetchDescriptor<Transaction>()), key: \.id)
            var budgets = try indexed(context.fetch(FetchDescriptor<Budget>()), key: \.id)
            var goals = try indexed(context.fetch(FetchDescriptor<SavingsGoal>()), key: \.id)
            var attachments = try indexed(context.fetch(FetchDescriptor<TransactionAttachment>()), key: \.id)
            let resolutions = try context.fetch(FetchDescriptor<RecurrenceResolution>())
            func owns(_ transaction: Transaction) -> Bool {
                let legs = [transaction.fromConto, transaction.toConto].compactMap { $0 }
                return !legs.isEmpty && legs.allSatisfy { $0.account?.id == localBookID }
            }
            // The owner retains both legs of cross-book transfers privately.
            // An unchanged shared projection must not sever that private leg.
            // Changed projections need explicit review before either book changes.
            let ownerProjection: [SharedRecordID: SharedBookRecord]
            if !memberships.isEmpty, memberships.allSatisfy(\.isOwner), localBookID == scope.bookID, books[localBookID] != nil {
                ownerProjection = Dictionary(uniqueKeysWithValues: try SharedBookExporter.export(bookID: localBookID, container: container).records.map { ($0.id, $0) })
            } else { ownerProjection = [:] }
            var preserved: Set<SharedRecordID> = []
            // Validate ownership before changing any relationship or triggering cascades.
            if books[localBookID] != nil && memberships.isEmpty { throw Failure.identityCollision }
            for record in records where record.id.kind != .recurrence {
                guard let uuid = ids[record.id] else { throw Failure.invalidGraph }
                switch record.id.kind {
                case .conto:
                    if let value = conti[uuid] {
                        guard value.account?.id == localBookID else { throw Failure.identityCollision }
                        if record.deleted, !((value.incomingTransactions ?? []) + (value.outgoingTransactions ?? [])).allSatisfy(owns) { throw Failure.protectedTransfer }
                    }
                case .category: if let value = categories[uuid], value.account?.id != localBookID { throw Failure.identityCollision }
                case .transaction:
                    if let value = transactions[uuid], !owns(value) {
                        guard !record.deleted, ownerProjection[record.id] == record else { throw Failure.protectedTransfer }
                        preserved.insert(record.id)
                    }
                case .budget: if let value = budgets[uuid], value.account?.id != localBookID { throw Failure.identityCollision }
                case .goal: if let value = goals[uuid], value.account?.id != localBookID { throw Failure.identityCollision }
                case .attachment:
                    if let value = attachments[uuid], value.transaction.map(owns) != true {
                        guard !record.deleted, ownerProjection[record.id] == record else { throw Failure.identityCollision }
                        preserved.insert(record.id)
                    }
                default: break
                }
            }
            // Cascades and nullification must not erase a child added locally
            // since the last reconciliation. Require every affected child in
            // the incoming graph, even when it will be moved to another parent.
            if !root.deleted {
                func covered(_ kind: SharedRecordID.Kind, _ identity: String) throws {
                    guard records.contains(where: { record in
                        record.id.kind == kind && (aliases[record.id.recordName] == identity || ids[record.id]?.uuidString.lowercased() == identity)
                    }) else { throw Failure.unreconciledDeletion }
                }
                for record in records where record.deleted {
                    guard let uuid = ids[record.id] else { continue }
                    switch record.id.kind {
                    case .conto:
                        for value in transactions.values where value.fromConto?.id == uuid || value.toConto?.id == uuid || value.fromContoId == uuid || value.toContoId == uuid {
                            try covered(.transaction, value.id.uuidString.lowercased())
                        }
                    case .category:
                        for value in transactions.values where value.category?.id == uuid || value.categoryId == uuid { try covered(.transaction, value.id.uuidString.lowercased()) }
                        for value in budgets.values where (value.categories ?? []).contains(where: { $0.id == uuid }) { try covered(.budget, value.id.uuidString.lowercased()) }
                        for value in categories.values where value.parentCategoryId == uuid { try covered(.category, value.id.uuidString.lowercased()) }
                    case .transaction:
                        for value in attachments.values where value.transaction?.id == uuid { try covered(.attachment, value.id.uuidString.lowercased()) }
                        for value in transactions.values where value.recurrenceSourceID == uuid { try covered(.transaction, value.id.uuidString.lowercased()) }
                        for value in resolutions where value.sourceID == uuid || value.transactionID == uuid { try covered(.recurrence, value.key) }
                    default: break
                    }
                }
            }
            if memberships.isEmpty {
                let membership = SharedBookMembership(scopeKey: scopeKey, ownerName: scope.ownerName, remoteBookID: scope.bookID, localBookID: localBookID)
                membership.importNamespace = namespace
                context.insert(membership)
            }
            if root.deleted {
                if let book = books[localBookID] {
                    let all = (book.conti ?? []).flatMap { ($0.incomingTransactions ?? []) + ($0.outgoingTransactions ?? []) }
                    guard all.allSatisfy(owns) else { throw Failure.protectedTransfer }
                    context.delete(book)
                }
                let resolutionKeys = Set(links.filter { $0.remoteRecordName.hasPrefix("recurrence:") }.map(\.localIdentity))
                for resolution in resolutions where resolutionKeys.contains(resolution.key) { context.delete(resolution) }
                try register(root, localIdentity: localBookID.uuidString.lowercased())
                try context.save()
                return localBookID
            }
            let book = books[localBookID] ?? Account(name: "")
            if books[localBookID] == nil { book.id = localBookID; context.insert(book); books[localBookID] = book }
            // Allocate the graph first; links may arrive in any record order.
            for record in records where !record.deleted && record.id.kind != .recurrence {
                guard let uuid = ids[record.id] else { throw Failure.invalidGraph }
                switch record.id.kind {
                case .book: break
                case .conto:
                    if conti[uuid] == nil { let value = Conto(name: "", type: .other); value.id = uuid; context.insert(value); conti[uuid] = value }
                case .category:
                    if categories[uuid] == nil { let value = Category(name: ""); value.id = uuid; context.insert(value); categories[uuid] = value }
                case .transaction:
                    if transactions[uuid] == nil { let value = Transaction(amount: 0, type: .expense); value.id = uuid; context.insert(value); transactions[uuid] = value }
                case .budget:
                    if budgets[uuid] == nil { let value = Budget(name: "", amount: 0, period: .monthly); value.id = uuid; context.insert(value); budgets[uuid] = value }
                case .goal:
                    if goals[uuid] == nil { let value = SavingsGoal(name: "", targetAmount: 0); value.id = uuid; context.insert(value); goals[uuid] = value }
                case .attachment:
                    if attachments[uuid] == nil { let value = TransactionAttachment(id: uuid, filename: "", contentType: "public.data", data: Data()); context.insert(value); attachments[uuid] = value }
                case .recurrence: break
                }
            }
            for record in records where !record.deleted {
                let uuid = ids[record.id]
                if preserved.contains(record.id), let uuid {
                    try register(record, localIdentity: uuid.uuidString.lowercased())
                    continue
                }
                switch record.id.kind {
                case .book:
                    book.name = try record.text("name"); book.currency = try record.text("currency")
                    book.externalID = try required(record.text("externalID"))
                    book.createdAt = try record.date("createdAt"); book.updatedAt = try record.date("updatedAt"); book.isActive = try record.flag("isActive")
                case .conto:
                    let value = try required(uuid.flatMap { conti[$0] }); value.account = book
                    try applyConto(record, to: value)
                case .category:
                    let value = try required(uuid.flatMap { categories[$0] }); value.account = book
                    value.externalID = try required(record.text("externalID")); value.name = try record.text("name")
                    value.color = try record.text("color"); value.icon = try record.text("icon")
                    value.createdAt = try record.date("createdAt"); value.updatedAt = try record.date("updatedAt")
                    value.isActive = try record.flag("isActive")
                    value.parentCategoryId = try localID(record.reference("parent", kind: .category))
                case .transaction:
                    let value = try required(uuid.flatMap { transactions[$0] })
                    try applyTransaction(record, to: value)
                    value.setFromConto(try localID(record.reference("fromConto", kind: .conto)).flatMap { conti[$0] })
                    value.setToConto(try localID(record.reference("toConto", kind: .conto)).flatMap { conti[$0] })
                    value.setCategory(try localID(record.reference("category", kind: .category)).flatMap { categories[$0] })
                    value.recurrenceSourceID = try localID(record.reference("recurrenceSource", kind: .transaction))
                case .budget:
                    let value = try required(uuid.flatMap { budgets[$0] }); value.account = book
                    value.externalID = try required(record.text("externalID")); value.name = try record.text("name")
                    value.amount = try record.decimal("amount"); value.period = try record.enumeration("period", BudgetPeriod.self)
                    value.isActive = try record.flag("isActive"); value.createdAt = try record.date("createdAt"); value.updatedAt = try record.date("updatedAt")
                    value.alertThreshold = try record.number("threshold"); value.includeRecurringTransactions = try record.flag("includeRecurring")
                    value.categories = try record.references("categories", kind: .category).map { try required(localID($0).flatMap { categories[$0] }) }
                case .goal:
                    let value = try required(uuid.flatMap { goals[$0] }); value.account = book
                    try applyGoal(record, to: value)
                case .attachment:
                    let value = try required(uuid.flatMap { attachments[$0] })
                    value.filename = try required(record.text("filename")); value.contentType = try required(record.text("contentType"))
                    value.createdAt = try required(record.date("createdAt")); value.data = assets[record.id]
                    value.transaction = try required(localID(record.reference("transaction", kind: .transaction)).flatMap { transactions[$0] })
                case .recurrence:
                    let sourceID = try required(localID(record.reference("source", kind: .transaction)))
                    let scheduled = try required(record.date("scheduledDate"))
                    let key = RecurrenceResolution.key(sourceID: sourceID, date: scheduled)
                    let matching = resolutions.filter { $0.key == key }
                    guard matching.count <= 1 else { throw Failure.identityCollision }
                    let value = matching.first ?? RecurrenceResolution(sourceID: sourceID, scheduledDate: scheduled)
                    if matching.isEmpty { context.insert(value) }
                    value.transactionID = try localID(record.reference("transaction", kind: .transaction))
                    value.isSkipped = try required(record.flag("isSkipped")); value.createdAt = try required(record.date("createdAt"))
                    try register(record, localIdentity: key)
                }
                if let uuid { try register(record, localIdentity: uuid.uuidString.lowercased()) }
            }
            for record in records where record.deleted {
                let uuid = ids[record.id]
                switch record.id.kind {
                case .book: break
                case .conto: if let value = uuid.flatMap({ conti[$0] }) { context.delete(value) }
                case .category: if let value = uuid.flatMap({ categories[$0] }) { context.delete(value) }
                case .transaction: if let value = uuid.flatMap({ transactions[$0] }) { context.delete(value) }
                case .budget: if let value = uuid.flatMap({ budgets[$0] }) { context.delete(value) }
                case .goal: if let value = uuid.flatMap({ goals[$0] }) { context.delete(value) }
                case .attachment: if let value = uuid.flatMap({ attachments[$0] }) { context.delete(value) }
                case .recurrence:
                    if let key = aliases[record.id.recordName] { for value in resolutions where value.key == key { context.delete(value) } }
                }
            }
            try context.save()
            return localBookID
        } catch {
            context.rollback()
            throw error
        }
    }

    private static func required<T>(_ value: T?) throws -> T {
        guard let value else { throw Failure.invalidGraph }
        return value
    }
    private static func indexed<T>(_ values: [T], key: KeyPath<T, UUID>) throws -> [UUID: T] {
        var result: [UUID: T] = [:]
        for value in values {
            guard result[value[keyPath: key]] == nil else { throw Failure.identityCollision }
            result[value[keyPath: key]] = value
        }
        return result
    }

    private static func validate(scope: SharedBookScope, records: [SharedBookRecord], assets: [SharedRecordID: Data]) throws -> [SharedRecordID: SharedBookRecord] {
        guard !scope.ownerName.isEmpty, scope.ownerName.utf8.count <= 255, !scope.ownerName.contains("\u{0}") else { throw Failure.invalidGraph }
        var graph: [SharedRecordID: SharedBookRecord] = [:]
        for record in records {
            guard record.version == 1, record.id.bookID == scope.bookID, graph[record.id] == nil,
                  !record.deleted || record.fields.isEmpty else { throw Failure.invalidGraph }
            if record.id.kind != .recurrence {
                guard let uuid = UUID(uuidString: record.id.entityID), uuid.uuidString.lowercased() == record.id.entityID else { throw Failure.invalidGraph }
            }
            graph[record.id] = record
        }
        let rootID = SharedRecordID(bookID: scope.bookID, kind: .book, entityID: scope.bookID.uuidString.lowercased())
        guard let root = graph[rootID], records.filter({ $0.id.kind == .book }).count == 1 else { throw Failure.invalidGraph }
        if root.deleted {
            guard records.allSatisfy(\.deleted) else { throw Failure.invalidGraph }
            return graph
        }
        for record in records where !record.deleted {
            for value in record.fields.values {
                let references: [SharedRecordID]
                switch value {
                case let .reference(reference): references = [reference]
                case let .references(list): references = list
                default: references = []
                }
                guard references.allSatisfy({ $0.bookID == scope.bookID && graph[$0]?.deleted == false }) else { throw Failure.invalidGraph }
            }
            switch record.id.kind {
            case .book: break
            case .conto, .category, .transaction, .budget, .goal:
                guard try record.reference("book", kind: .book) == rootID else { throw Failure.invalidGraph }
            case .attachment:
                guard try record.reference("transaction", kind: .transaction) != nil,
                      let bytes = assets[record.id], bytes.count <= 10 * 1024 * 1024 else { throw Failure.invalidAsset }
                let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
                guard try record.text("contentDigest") == digest else { throw Failure.invalidAsset }
            case .recurrence:
                let source = try required(record.reference("source", kind: .transaction))
                let scheduled = try required(record.date("scheduledDate"))
                let sourceID = try required(UUID(uuidString: source.entityID))
                guard record.id.entityID == RecurrenceResolution.key(sourceID: sourceID, date: scheduled) else { throw Failure.invalidGraph }
            }
            if record.id.kind == .transaction {
                let type = try required(record.enumeration("type", TransactionType.self))
                let from = try record.reference("fromConto", kind: .conto), to = try record.reference("toConto", kind: .conto)
                switch type {
                case .expense: guard from != nil, to == nil else { throw Failure.invalidGraph }
                case .income: guard to != nil, from == nil else { throw Failure.invalidGraph }
                case .transfer: guard from != nil || to != nil else { throw Failure.invalidGraph }
                }
            }
            if record.id.kind == .category {
                var visited: Set<SharedRecordID> = [record.id]
                var parent = try record.reference("parent", kind: .category)
                while let id = parent {
                    guard visited.insert(id).inserted, let next = graph[id] else { throw Failure.invalidGraph }
                    parent = try next.reference("parent", kind: .category)
                }
            }
        }
        return graph
    }

    private static func applyConto(_ record: SharedBookRecord, to value: Conto) throws {
        value.externalID = try required(record.text("externalID"))
        value.name = try record.text("name")
        value.type = try record.enumeration("type", ContoType.self)
        value.initialBalance = try record.decimal("initialBalance")
        value.createdAt = try record.date("createdAt")
        value.updatedAt = try record.date("updatedAt")
        value.isActive = try record.flag("isActive")
        value.contoDescription = try record.text("description")
        value.color = try record.text("color")
        value.creditLimit = try record.decimal("creditLimit")
        value.statementClosingDay = try record.integer("statementClosingDay")
        value.paymentDueDay = try record.integer("paymentDueDay")
        value.annualInterestRate = try record.decimal("annualInterestRate")
        value.savingsGoal = try record.decimal("savingsGoal")
    }

    private static func applyTransaction(_ record: SharedBookRecord, to value: Transaction) throws {
        value.externalID = try required(record.text("externalID"))
        value.amount = try record.decimal("amount")
        value.destinationAmount = try record.decimal("destinationAmount")
        value.date = try required(record.date("date"))
        value.createdAt = try record.date("createdAt")
        value.updatedAt = try record.date("updatedAt")
        value.transactionDescription = try record.text("description")
        value.notes = try record.text("notes")
        value.type = try required(record.enumeration("type", TransactionType.self))
        value.originalAmount = try record.decimal("originalAmount")
        value.originalCurrency = try record.text("originalCurrency")
        value.exchangeRate = try record.decimal("exchangeRate")
        value.exchangeRateDate = try record.text("exchangeRateDate")
        value.exchangeRateSource = try record.text("exchangeRateSource")
        value.placeName = try record.text("placeName")
        value.latitude = try record.number("latitude")
        value.longitude = try record.number("longitude")
        value.locationAccuracy = try record.number("locationAccuracy")
        value.isRecurring = try record.flag("isRecurring")
        value.recurrenceFrequency = try record.enumeration("recurrenceFrequency", RecurrenceFrequency.self)
        value.recurrenceEndDate = try record.date("recurrenceEndDate")
    }

    private static func applyGoal(_ record: SharedBookRecord, to value: SavingsGoal) throws {
        value.externalID = try required(record.text("externalID"))
        value.name = try record.text("name")
        value.targetAmount = try record.decimal("targetAmount")
        value.currentAmount = try record.decimal("currentAmount")
        value.targetDate = try record.date("targetDate")
        value.category = try record.enumeration("category", SavingsGoalCategory.self)
        value.status = try record.enumeration("status", SavingsGoalStatus.self)
        value.createdAt = try record.date("createdAt")
        value.updatedAt = try record.date("updatedAt")
        value.goalDescription = try record.text("description")
        value.isActive = try record.flag("isActive")
    }
}
