import Foundation
import SwiftData
import CryptoKit

/// Category edits use their own context and one save, preserving ledger/budget references.
@MainActor
public enum FormiCLICategoryService {
    public struct Row: Codable, Sendable, Equatable {
        public let id: UUID
        public let bookID: UUID
        public var name: String
        public var color: String
        public var icon: String
        public var parentID: UUID?
        public var type: String
        public var active: Bool
        public let updatedAt: Date?

        init(_ category: Category, bookID: UUID) {
            id = category.id; self.bookID = bookID
            name = category.name ?? ""; color = category.color ?? CategoryPalette.fallback
            icon = category.icon ?? "tag"; parentID = category.parentCategoryId
            type = category.kindRaw ?? "both"; active = category.isActive == true
            updatedAt = category.updatedAt
        }
        init(id: UUID, bookID: UUID, name: String) {
            self.id = id; self.bookID = bookID; self.name = name
            color = CategoryPalette.fallback; icon = "tag"; parentID = nil
            type = "both"; active = true; updatedAt = nil
        }
    }
    public struct Change: Codable, Sendable {
        public let before: Row?
        public let after: Row
    }
    public struct Result: Codable, Sendable {
        public let saved: Bool
        public let alreadyRecorded: Bool
        public let categoryID: UUID
        /// Pass the preview revision back with --revision when committing.
        public let revision: String
        public let changes: [Change]
    }

    public static func rows(_ categories: [Category], bookID: UUID) -> [Row] {
        categories.filter { $0.account?.id == bookID }.map { Row($0, bookID: bookID) }
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }
    public static func revision(_ categories: [Category], bookID: UUID) throws -> String {
        // Include the entire taxonomy, even archived children and updatedAt, to catch stale plans.
        Data(SHA256.hash(data: try FormiCLIWire.encoder().encode(rows(categories, bookID: bookID))))
            .map { String(format: "%02x", $0) }.joined()
    }

    public static func execute(_ request: FormiCLIRequest, container: ModelContainer) throws -> Result {
        typealias Failure = FormiCLIService.Failure
        guard request.version == 1, ["category-create", "category-update"].contains(request.command),
              request.movements.isEmpty, !request.allowDuplicates,
              let input = request.categoryMutation, let bookID = request.bookID else {
            throw Failure("Richiesta categoria non valida.")
        }
        let creating = request.command == "category-create"
        guard creating ? (input.categoryID == nil && input.name != nil) : input.categoryID != nil else {
            throw Failure("Specifica nome per creare o UUID categoria per modificare.")
        }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        guard let book = try context.fetch(FetchDescriptor<Account>()).first(where: { $0.id == bookID && $0.isActive == true }),
              try !context.fetch(FetchDescriptor<SharedBookMembership>()).contains(where: { $0.localBookID == bookID }) else {
            throw Failure("Libro non disponibile: la CLI modifica solo libri personali attivi.")
        }
        let all = try context.fetch(FetchDescriptor<Category>())
        let currentRevision = try revision(all, bookID: bookID)
        // Domain-separated digest prevents a movement's requestID being reused as a category edit.
        var digestData = Data("formi-category:\(request.command):\(bookID.uuidString):".utf8)
        digestData.append(try FormiCLIWire.encoder().encode(input))
        let digest = Data(SHA256.hash(data: digestData))
        let requestID = input.requestID
        if let receipt = try context.fetch(FetchDescriptor<RemoteExpenseReceipt>(predicate: #Predicate { $0.requestID == requestID })).first {
            guard receipt.requestDigest == digest, let resultID = receipt.transactionID else {
                throw Failure("requestID già utilizzato con dati diversi. Per una nuova modifica usa un nuovo UUID.")
            }
            // A retry must not undo later edits or recreate deleted categories.
            return Result(saved: request.commit, alreadyRecorded: true, categoryID: resultID,
                          revision: currentRevision, changes: [])
        }
        if let expected = input.revision, expected != currentRevision {
            throw Failure("Categorie cambiate dopo l'anteprima. Rileggi categories e genera una nuova anteprima.")
        }
        if request.commit && input.revision == nil {
            throw Failure("Prima esegui l'anteprima; per salvare aggiungi --revision con il valore restituito e --yes.")
        }
        let existing = creating ? nil : all.first { $0.id == input.categoryID && $0.account?.id == bookID }
        guard creating || existing != nil else { throw Failure("Categoria non trovata nel libro indicato.") }
        guard creating || input.name != nil || input.color != nil || input.icon != nil ||
              input.parent != nil || input.type != nil || input.active != nil else {
            throw Failure("Specifica almeno un campo da modificare.")
        }
        // Stable create ID lets the preview show the final UUID without inserting anything.
        let id = existing?.id ?? input.requestID
        guard !creating || !all.contains(where: { $0.id == id }) else { throw Failure("UUID di creazione già presente.") }
        var after = existing.map { Row($0, bookID: bookID) } ?? Row(id: id, bookID: bookID, name: "")
        if let name = input.name {
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name.count <= 200, !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                throw Failure("Nome non valido: usa da 1 a 200 caratteri senza caratteri di controllo.")
            }
            after.name = name
        }
        if let color = input.color {
            guard color.range(of: #"^#[0-9A-Fa-f]{6}$"#, options: .regularExpression) != nil else {
                throw Failure("Colore non valido: usa #RRGGBB.")
            }
            after.color = color.uppercased()
        }
        if let icon = input.icon {
            guard !icon.isEmpty, icon.count <= 150,
                  icon.range(of: #"^[a-zA-Z0-9.-]+$"#, options: .regularExpression) != nil else {
                throw Failure("Icona non valida: usa il nome di un SF Symbol.")
            }
            after.icon = icon
        }
        if let type = input.type {
            guard ["expense", "income", "both"].contains(type) else { throw Failure("Tipo non valido.") }
            after.type = type
        }
        if let active = input.active { after.active = active }
        if let parent = input.parent {
            guard parent == "none" || UUID(uuidString: parent) != nil else { throw Failure("Genitore non valido.") }
            after.parentID = parent == "none" ? nil : UUID(uuidString: parent)
        }
        let children = all.filter { $0.account?.id == bookID && $0.parentCategoryId == id }
        if let parentID = after.parentID {
            guard parentID != id, let parent = all.first(where: { $0.id == parentID && $0.account?.id == bookID }),
                  parent.parentCategoryId == nil, !after.active || parent.isActive == true,
                  children.isEmpty else {
                throw Failure("Il genitore deve essere una categoria principale dello stesso libro (attiva per figli attivi). Sposta prima tutti i figli, anche archiviati: sono ammessi due livelli.")
            }
            let inherited = parent.kindRaw ?? "both"
            guard input.type == nil || input.type == inherited else {
                throw Failure("La sottocategoria eredita il tipo del genitore. Modifica il tipo della categoria principale.")
            }
            after.type = inherited
        }
        // Same-name siblings would be ambiguous for humans and AI.
        guard existing?.name == after.name && existing?.parentCategoryId == after.parentID || !all.contains(where: { $0.id != id && $0.account?.id == bookID &&
            $0.parentCategoryId == after.parentID && ($0.name ?? "").compare(after.name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) else {
            throw Failure("Esiste già una categoria con questo nome nella stessa posizione, anche archiviata.")
        }
        var changes = [Change(before: existing.map { Row($0, bookID: bookID) }, after: after)]
        for child in children.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            let before = Row(child, bookID: bookID)
            var next = before
            next.type = after.type
            if !after.active { next.active = false }
            if next != before { changes.append(Change(before: before, after: next)) }
        }
        // Check both denormalized IDs and relationships, including scheduled/recurring rows.
        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        for change in changes where change.before?.type != change.after.type && change.after.type != "both" {
            guard !transactions.contains(where: { ($0.categoryId == change.after.id || $0.category?.id == change.after.id) &&
                $0.type.rawValue != change.after.type }) else {
                throw Failure("Il nuovo tipo è incompatibile con movimenti esistenti di \(change.after.name). Usa both oppure riclassifica prima i movimenti.")
            }
        }
        if request.commit {
            let now = Date()
            for change in changes {
                let row = change.after
                let category: Category
                if let found = all.first(where: { $0.id == row.id }) { category = found }
                else {
                    category = Category(name: row.name); category.id = row.id; category.account = book
                    context.insert(category)
                }
                category.name = row.name; category.color = row.color; category.icon = row.icon
                category.parentCategoryId = row.parentID; category.kindRaw = row.type == "both" ? nil : row.type
                category.isActive = row.active; category.updatedAt = now
            }
            // Legacy receipt field stores the resulting entity UUID; domain digest distinguishes its kind.
            context.insert(RemoteExpenseReceipt(requestID: requestID, transactionID: id, requestDigest: digest, createdAt: now))
            do { try context.save() } catch { context.rollback(); throw error }
        }
        return Result(saved: request.commit, alreadyRecorded: false, categoryID: id,
                      revision: currentRevision, changes: changes)
    }
}
