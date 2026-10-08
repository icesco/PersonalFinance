import Foundation
import SwiftData
import Testing
@testable import FinanceCore

@MainActor
struct FormiCLICategoryTests {
    private struct Fixture {
        let container: ModelContainer
        let book: UUID
        let root: UUID
        let child: UUID
        let other: UUID
    }
    private func fixture() throws -> Fixture {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let book = Account(name: "Personale", currency: "EUR")
        let root = FinanceCore.Category(name: "Casa", kind: .expense)
        let child = FinanceCore.Category(name: "Affitto", parentCategoryId: root.id, kind: .expense)
        let other = FinanceCore.Category(name: "Altro")
        for category in [root, child, other] { category.account = book }
        book.categories = [root, child, other]
        container.mainContext.insert(book)
        try container.mainContext.save()
        return Fixture(container: container, book: book.id, root: root.id, child: child.id, other: other.id)
    }
    private func request(_ f: Fixture, id: UUID? = nil, name: String? = nil,
                         parent: String? = nil, type: String? = nil, active: Bool? = nil) -> FormiCLIRequest {
        var request = FormiCLIRequest(command: id == nil ? "category-create" : "category-update", bookID: f.book)
        request.categoryMutation = .init(requestID: UUID(), categoryID: id, name: name, parent: parent, type: type, active: active)
        return request
    }
    private func commit(_ input: FormiCLIRequest, _ f: Fixture) throws -> FormiCLIRequest {
        var input = input
        let preview = try FormiCLICategoryService.execute(input, container: f.container)
        input.categoryMutation?.revision = preview.revision; input.commit = true
        _ = try FormiCLICategoryService.execute(input, container: f.container)
        return input
    }
    private func row(_ f: Fixture, _ id: UUID) throws -> FinanceCore.Category {
        try #require(ModelContext(f.container).fetch(FetchDescriptor<FinanceCore.Category>()).first { $0.id == id })
    }

    @Test func creationPreviewAndRetryPreserveLaterEditsAndDeletion() throws {
        let f = try fixture()
        let input = request(f, name: "Sport", parent: f.root.uuidString)
        let preview = try FormiCLICategoryService.execute(input, container: f.container)
        #expect(!preview.saved)
        #expect(preview.changes[0].after.type == "expense")
        #expect(try ModelContext(f.container).fetchCount(FetchDescriptor<FinanceCore.Category>()) == 3)
        let saved = try commit(input, f)
        let id = try #require(saved.categoryMutation?.requestID)
        #expect(try row(f, id).parentCategoryId == f.root)
        let context = ModelContext(f.container)
        let category = try #require(context.fetch(FetchDescriptor<FinanceCore.Category>()).first { $0.id == id })
        category.name = "Modificato nell'app"; try context.save()
        #expect(try FormiCLICategoryService.execute(saved, container: f.container).alreadyRecorded)
        #expect(try row(f, id).name == "Modificato nell'app")
        context.delete(category); try context.save()
        #expect(try FormiCLICategoryService.execute(saved, container: f.container).alreadyRecorded)
        #expect(try ModelContext(f.container).fetchCount(FetchDescriptor<FinanceCore.Category>()) == 3)
        var changed = saved; changed.categoryMutation?.name = "Dati differenti"
        #expect(throws: FormiCLIService.Failure.self) { try FormiCLICategoryService.execute(changed, container: f.container) }
    }

    @Test func movePromoteAndEditAllFieldsPreserveReferences() throws {
        let f = try fixture()
        let context = ModelContext(f.container)
        let child = try #require(context.fetch(FetchDescriptor<FinanceCore.Category>()).first { $0.id == f.child })
        let transaction = Transaction(amount: 50, type: .expense, date: Date())
        transaction.setCategory(child)
        let budget = Budget(name: "Casa", amount: 200, period: .monthly)
        budget.categories = [child]
        context.insert(transaction); context.insert(budget); try context.save()
        var input = request(f, id: f.child, name: "Nuovo affitto", parent: f.other.uuidString)
        input.categoryMutation?.color = "#abcdef"; input.categoryMutation?.icon = "house"
        _ = try commit(input, f)
        let moved = try row(f, f.child)
        #expect(moved.parentCategoryId == f.other)
        #expect(moved.name == "Nuovo affitto" && moved.color == "#ABCDEF" && moved.icon == "house")
        #expect(moved.kind == nil)
        let fresh = ModelContext(f.container)
        #expect(try fresh.fetch(FetchDescriptor<Transaction>()).first?.categoryId == f.child)
        #expect(try fresh.fetch(FetchDescriptor<Budget>()).first?.categories?.first?.id == f.child)
        _ = try commit(request(f, id: f.child, parent: "none", type: "expense"), f)
        #expect(try row(f, f.child).parentCategoryId == nil)
        _ = try commit(request(f, id: f.root, parent: f.other.uuidString), f)
        #expect(try row(f, f.root).parentCategoryId == f.other)
    }

    @Test func cyclesGrandchildrenAndCrossBookParentsAreRejectedWithoutWrites() throws {
        let f = try fixture()
        let book = Account(name: "Secondo", currency: "EUR")
        let foreign = FinanceCore.Category(name: "Estero"); foreign.account = book; book.categories = [foreign]
        f.container.mainContext.insert(book); try f.container.mainContext.save()
        for input in [request(f, id: f.root, parent: f.root.uuidString),
                      request(f, id: f.root, parent: f.child.uuidString),
                      request(f, id: f.root, parent: f.other.uuidString),
                      request(f, id: f.child, parent: foreign.id.uuidString),
                      request(f, name: "Terzo livello", parent: f.child.uuidString)] {
            #expect(throws: FormiCLIService.Failure.self) { try FormiCLICategoryService.execute(input, container: f.container) }
        }
        #expect(try row(f, f.root).parentCategoryId == nil)
        #expect(try ModelContext(f.container).fetchCount(FetchDescriptor<RemoteExpenseReceipt>()) == 0)
    }

    @Test func archiveCascadesAndRestoreIsExplicitForEachChild() throws {
        let f = try fixture()
        let preview = try FormiCLICategoryService.execute(request(f, id: f.root, active: false), container: f.container)
        #expect(preview.changes.count == 2)
        _ = try commit(request(f, id: f.root, active: false), f)
        #expect(try row(f, f.root).isActive == false)
        #expect(try row(f, f.child).isActive == false)
        #expect(throws: FormiCLIService.Failure.self) {
            try FormiCLICategoryService.execute(request(f, id: f.child, active: true), container: f.container)
        }
        // Even an archived child prevents a third level from being introduced.
        #expect(throws: FormiCLIService.Failure.self) {
            try FormiCLICategoryService.execute(request(f, id: f.root, parent: f.other.uuidString), container: f.container)
        }
        _ = try commit(request(f, id: f.root, active: true), f)
        #expect(try row(f, f.child).isActive == false)
        _ = try commit(request(f, id: f.child, active: true), f)
        #expect(try row(f, f.child).isActive == true)
    }

    @Test func typePropagationChecksChildTransactionsIncludingDenormalizedIDs() throws {
        let f = try fixture()
        let transaction = Transaction(amount: 20, type: .expense, date: Date())
        transaction.categoryId = f.child
        f.container.mainContext.insert(transaction); try f.container.mainContext.save()
        #expect(throws: FormiCLIService.Failure.self) {
            try FormiCLICategoryService.execute(request(f, id: f.root, type: "income"), container: f.container)
        }
        #expect(try row(f, f.root).kind == .expense)
        #expect(throws: FormiCLIService.Failure.self) {
            try FormiCLICategoryService.execute(request(f, id: f.child, type: "both"), container: f.container)
        }
        _ = try commit(request(f, id: f.root, type: "both"), f)
        #expect(try row(f, f.child).kind == nil)
        #expect(try row(f, f.child).updatedAt != nil)
    }

    @Test func stalePreviewAndMissingRevisionCannotCommit() throws {
        let f = try fixture()
        var input = request(f, id: f.child, name: "Nuovo")
        let preview = try FormiCLICategoryService.execute(input, container: f.container)
        input.commit = true
        #expect(throws: FormiCLIService.Failure.self) { try FormiCLICategoryService.execute(input, container: f.container) }
        input.categoryMutation?.revision = preview.revision
        _ = try commit(request(f, id: f.other, name: "Cambiato altrove"), f)
        #expect(throws: FormiCLIService.Failure.self) { try FormiCLICategoryService.execute(input, container: f.container) }
        #expect(try row(f, f.child).name == "Affitto")
    }

    @Test func duplicateNamesBadFieldsAndSharedBooksAreRejected() throws {
        let f = try fixture()
        var badColor = request(f, name: "Nuovo"); badColor.categoryMutation?.color = "red"
        var badIcon = request(f, name: "Nuovo"); badIcon.categoryMutation?.icon = "bad icon"
        for input in [request(f, name: " casa "), request(f, name: " "), badColor, badIcon] {
            #expect(throws: FormiCLIService.Failure.self) { try FormiCLICategoryService.execute(input, container: f.container) }
        }
        f.container.mainContext.insert(SharedBookMembership(scopeKey: "test", ownerName: "owner", remoteBookID: UUID(), localBookID: f.book))
        try f.container.mainContext.save()
        #expect(throws: FormiCLIService.Failure.self) {
            try FormiCLICategoryService.execute(request(f, id: f.child, name: "Vietato"), container: f.container)
        }
        #expect(try row(f, f.child).name == "Affitto")
    }

    @Test func parserRequiresStableIDsAndPreservesOmittedFields() throws {
        let book = UUID().uuidString; let id = UUID().uuidString
        let args = ["category-update", "--book", book, "--category", id, "--request-id", UUID().uuidString, "--parent", "none", "--active", "false"]
        let parsed = try FormiCLIArguments.parse(args, read: { _ in Data() }, today: "2026-10-08")
        #expect(parsed.categoryMutation?.parent == "none")
        #expect(parsed.categoryMutation?.active == false && parsed.categoryMutation?.name == nil)
        #expect(!parsed.commit && parsed.movements.isEmpty)
        for args in [["category-create", "--book", book, "--name", "Casa"],
                     ["category-update", "--book", book, "--category", id, "--request-id", id],
                     args + ["--active", "true"], args + ["--allow-duplicates"],
                     ["category-create", "--book", book, "--name", "Casa", "--request-id", id, "--type", "transfer"]] {
            #expect(throws: FormiCLIArguments.Failure.self) {
                try FormiCLIArguments.parse(args, read: { _ in Data() }, today: "2026-10-08")
            }
        }
        #expect(try FormiCLIArguments.parse(["categories", "--include-archived"], read: { _ in Data() }, today: "2026-10-08").includeArchived == true)
    }
}
