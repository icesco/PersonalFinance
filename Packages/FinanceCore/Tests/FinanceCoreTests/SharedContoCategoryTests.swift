import Foundation
import SwiftData
import Testing
@testable import FinanceCore

@MainActor
struct SharedContoCategoryTests {
    private func fixture() throws -> (ModelContainer, SharedBookScope, UUID, UUID, UUID, UUID) {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let book = Account(name: "Personale")
        let personal = Conto(name: "Privato", type: .checking)
        let shared = Conto(name: "Casa", type: .checking)
        personal.account = book; shared.account = book
        let parent = FinanceCore.Category(name: "Casa", kind: .expense); parent.account = book
        let child = FinanceCore.Category(name: "Alimentari", parentCategoryId: parent.id, kind: .expense); child.account = book
        container.mainContext.insert(book); container.mainContext.insert(personal); container.mainContext.insert(shared)
        container.mainContext.insert(parent); container.mainContext.insert(child)
        let privateExpense = Transaction(amount: 10, type: .expense); privateExpense.setFromConto(personal); privateExpense.setCategory(child)
        let sharedExpense = Transaction(amount: 20, type: .expense); sharedExpense.setFromConto(shared); sharedExpense.setCategory(child)
        container.mainContext.insert(privateExpense); container.mainContext.insert(sharedExpense)
        let budget = Budget(name: "Personale", amount: 100, period: .monthly); budget.account = book; budget.categories = [child]
        container.mainContext.insert(budget); try container.mainContext.save()
        let scope = try SharedBookOwnerRegistration.register(bookID: book.id, contoID: shared.id, ownerRecordName: "owner", container: container)
        return (container, scope, shared.id, personal.id, child.id, privateExpense.id)
    }

    @Test func sharingCopiesUsedHierarchyWithoutChangingPersonalMovementsOrBudget() throws {
        let (container, scope, sharedID, _, personalCategoryID, privateExpenseID) = try fixture()
        let context = ModelContext(container)
        let categories = try context.fetch(FetchDescriptor<FinanceCore.Category>())
        let shared = categories.filter { $0.sharedContoID == sharedID }
        #expect(shared.count == 2 && categories.count == 4)
        let child = try #require(shared.first { $0.name == "Alimentari" })
        #expect(child.id != personalCategoryID && child.parentCategoryId == shared.first { $0.name == "Casa" }?.id)
        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        #expect(transactions.first { $0.id == privateExpenseID }?.categoryId == personalCategoryID)
        #expect(transactions.first { $0.fromContoId == sharedID }?.categoryId == child.id)
        #expect(try context.fetch(FetchDescriptor<Budget>()).first?.categories?.first?.id == personalCategoryID)
        _ = try SharedBookParticipantExporter.export(scope: scope, container: container)
        _ = try SharedBookParticipantExporter.export(scope: scope, container: container)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<FinanceCore.Category>()) == 4)
    }

    @Test func eachContoOffersOnlyItsOwnCategoriesAndSharedRenameIsIsolated() throws {
        let (container, _, sharedID, personalID, personalCategoryID, _) = try fixture()
        let context = container.mainContext
        let categories = try context.fetch(FetchDescriptor<FinanceCore.Category>())
        let shared = try #require(context.fetch(FetchDescriptor<Conto>()).first { $0.id == sharedID })
        let personal = try #require(context.fetch(FetchDescriptor<Conto>()).first { $0.id == personalID })
        let visible = SharedContoCategories.available(for: shared, in: categories)
        #expect(visible.count == 2 && visible.allSatisfy { $0.sharedContoID == sharedID })
        #expect(SharedContoCategories.available(for: personal, in: categories).allSatisfy { $0.sharedContoID == nil })
        let sharedChild = try #require(visible.first { $0.name == "Alimentari" })
        try SettingsEdits(context: context).updateCategory(sharedChild, name: "Spesa di casa", color: CategoryPalette.fallback, icon: "cart")
        #expect(categories.first { $0.id == personalCategoryID }?.name == "Alimentari")
    }

    @Test func unusedNewCategoriesAreExportedImportedAndRemainScopedAfterPlacement() throws {
        let (owner, scope, sharedID, _, _, _) = try fixture()
        let context = owner.mainContext
        let conto = try #require(context.fetch(FetchDescriptor<Conto>()).first { $0.id == sharedID })
        let book = try #require(conto.account)
        _ = try SettingsEdits(context: context).createCategory(name: "Bollette", color: CategoryPalette.fallback, icon: "bolt",
            parentID: nil, kind: .expense, account: book, sharedContoID: sharedID)
        let snapshot = try SharedBookParticipantExporter.export(scope: scope, container: owner)
        #expect(snapshot.records.contains { $0.id.kind == .category && $0.fields["name"] == .text("Bollette") })
        let receiver = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        try SharedBookImporter.apply(scope: scope, records: snapshot.records, assets: snapshot.assets, container: receiver)
        let personalBook = Account(name: "Mio libro"); receiver.mainContext.insert(personalBook); try receiver.mainContext.save()
        try SharedContoPlacement.completeAcceptance(scope: scope, destination: .existing(personalBook.id), container: receiver)
        let fresh = ModelContext(receiver)
        let member = try #require(fresh.fetch(FetchDescriptor<SharedBookMembership>()).first)
        #expect(try fresh.fetch(FetchDescriptor<FinanceCore.Category>()).allSatisfy { $0.sharedContoID == member.localContoID && $0.account?.id == personalBook.id })
        #expect(try SharedBookParticipantExporter.export(scope: scope, container: receiver).records == snapshot.records)
    }

    @Test func newSharedSubcategoryKeepsHierarchyThroughParticipantRoundTrip() throws {
        let (owner, scope, sharedID, _, _, _) = try fixture()
        let context = owner.mainContext
        let conto = try #require(context.fetch(FetchDescriptor<Conto>()).first { $0.id == sharedID })
        let book = try #require(conto.account)
        let edits = SettingsEdits(context: context)
        let parent = try edits.createCategory(name: "Trasporti", color: "#123456", icon: "car",
            parentID: nil, kind: .expense, account: book, sharedContoID: sharedID)
        _ = try edits.createCategory(name: "Carburante", color: "#123456", icon: "fuelpump",
            parentID: parent.id, kind: .income, account: book, sharedContoID: sharedID)
        let snapshot = try SharedBookParticipantExporter.export(scope: scope, container: owner)
        let receiver = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        try SharedBookImporter.apply(scope: scope, records: snapshot.records, assets: snapshot.assets, container: receiver)
        let categories = try receiver.mainContext.fetch(FetchDescriptor<FinanceCore.Category>())
        let importedParent = try #require(categories.first { $0.name == "Trasporti" })
        let importedChild = try #require(categories.first { $0.name == "Carburante" })
        #expect(importedChild.parentCategoryId == importedParent.id)
        #expect(importedChild.sharedContoID == importedParent.sharedContoID)
        #expect(importedChild.kind == .expense)
        try SettingsEdits(context: receiver.mainContext).updateCategory(importedChild,
            name: "Benzina", color: "#123456", icon: "fuelpump")
        let returned = try SharedBookParticipantExporter.export(scope: scope, container: receiver)
        try SharedBookImporter.apply(scope: scope, records: returned.records, assets: returned.assets, container: owner)
        let fresh = try ModelContext(owner).fetch(FetchDescriptor<FinanceCore.Category>())
        let edited = try #require(fresh.first { $0.name == "Benzina" })
        #expect(edited.parentCategoryId == parent.id && edited.sharedContoID == sharedID)
    }

    @Test func personalCategoryCannotBeUsedForSharedVoiceMovementOrAsSharedParent() throws {
        let (container, _, sharedID, _, privateCategoryID, _) = try fixture()
        let context = container.mainContext
        let conto = try #require(context.fetch(FetchDescriptor<Conto>()).first { $0.id == sharedID })
        let book = try #require(conto.account)
        let invalid = VoiceTransactionDraft(amount: "25", currency: "EUR", type: .expense, contoID: sharedID, categoryID: privateCategoryID)
        #expect(throws: (any Error).self) { try VoiceTransactionApproval.approve([invalid], in: container) }
        #expect(throws: (any Error).self) {
            try SettingsEdits(context: context).createCategory(name: "Errore", color: CategoryPalette.fallback, icon: "tag",
                parentID: privateCategoryID, kind: .expense, account: book, sharedContoID: sharedID)
        }
        let category = try #require(context.fetch(FetchDescriptor<FinanceCore.Category>()).first { $0.sharedContoID == sharedID && $0.name == "Alimentari" })
        let valid = VoiceTransactionDraft(amount: "25", currency: "EUR", type: .expense, contoID: sharedID, categoryID: category.id)
        #expect(try VoiceTransactionApproval.approve([valid], in: container).count == 1)
    }
    @Test func selectedPersonalCategoriesFromAnotherBookCopyHierarchyWithoutMovingOriginals() throws {
        let (container, scope, contoID, _, _, _) = try fixture()
        let context = container.mainContext
        let sourceBook = Account(name: "Altro libro")
        let parent = FinanceCore.Category(name: "Trasporti", color: "#123456", icon: "car", kind: .expense)
        let child = FinanceCore.Category(name: "Carburante", icon: "fuelpump", parentCategoryId: parent.id, kind: .expense)
        parent.account = sourceBook; child.account = sourceBook
        let unselected = FinanceCore.Category(name: "Non selezionata"); unselected.account = sourceBook
        context.insert(sourceBook); context.insert(parent); context.insert(child); context.insert(unselected); try context.save()
        let count = try SharedContoCategories.copyPersonalCategories(contoID: contoID, categoryIDs: [child.id], container: container)
        #expect(count == 2)
        let fresh = ModelContext(container)
        let shared = try fresh.fetch(FetchDescriptor<FinanceCore.Category>()).filter { $0.sharedContoID == contoID }
        let copiedParent = try #require(shared.first { $0.name == "Trasporti" })
        let copiedChild = try #require(shared.first { $0.name == "Carburante" })
        #expect(copiedParent.id != parent.id && copiedChild.id != child.id)
        #expect(copiedChild.parentCategoryId == copiedParent.id && copiedParent.icon == "car" && copiedParent.color == "#123456")
        #expect(copiedParent.account?.id != sourceBook.id && copiedChild.kind == .expense)
        #expect(!shared.contains { $0.name == "Non selezionata" })
        #expect(try fresh.fetch(FetchDescriptor<FinanceCore.Category>()).first { $0.id == child.id }?.account?.id == sourceBook.id)
        let snapshot = try SharedBookParticipantExporter.export(scope: scope, container: container)
        #expect(snapshot.records.contains { $0.fields["name"] == .text("Carburante") })
    }

    @Test func repeatedManualCopyKeepsIndependentEditsAndDoesNotDuplicateAutomaticCopies() throws {
        let (container, _, contoID, _, originalID, _) = try fixture()
        #expect(try SharedContoCategories.copyPersonalCategories(contoID: contoID, categoryIDs: [originalID], container: container) == 0)
        let context = container.mainContext
        let categories = try context.fetch(FetchDescriptor<FinanceCore.Category>())
        let copied = try #require(categories.first { $0.sharedContoID == contoID && $0.name == "Alimentari" })
        let original = try #require(categories.first { $0.id == originalID })
        copied.name = "Spesa condivisa"; original.name = "Spesa personale"; try context.save()
        #expect(try SharedContoCategories.copyPersonalCategories(contoID: contoID, categoryIDs: [originalID], container: container) == 0)
        let after = try ModelContext(container).fetch(FetchDescriptor<FinanceCore.Category>())
        #expect(after.count == categories.count)
        #expect(after.first { $0.id == copied.id }?.name == "Spesa condivisa")
        #expect(after.first { $0.id == originalID }?.name == "Spesa personale")
    }

    @Test func invalidSelectionCannotCopySharedOrArchivedCategoriesAndRollsBack() throws {
        let (container, _, contoID, _, originalID, _) = try fixture()
        let context = container.mainContext
        let scoped = try #require(context.fetch(FetchDescriptor<FinanceCore.Category>()).first { $0.sharedContoID == contoID })
        let archived = FinanceCore.Category(name: "Archiviata"); archived.account = scoped.account; archived.isActive = false
        context.insert(archived); try context.save()
        let before = try context.fetchCount(FetchDescriptor<FinanceCore.Category>())
        #expect(throws: (any Error).self) { try SharedContoCategories.copyPersonalCategories(contoID: contoID, categoryIDs: [originalID, scoped.id], container: container) }
        #expect(throws: (any Error).self) { try SharedContoCategories.copyPersonalCategories(contoID: contoID, categoryIDs: [archived.id], container: container) }
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<FinanceCore.Category>()) == before)
    }

    @Test func sharedSuggestionsStayScopedAndPreserveExistingCategoriesAndPrivateBudget() throws {
        let (container, scope, sharedID, _, personalCategoryID, _) = try fixture()
        let context = container.mainContext
        let conto = try #require(context.fetch(FetchDescriptor<Conto>()).first { $0.id == sharedID })
        let original = try #require(context.fetch(FetchDescriptor<FinanceCore.Category>()).first {
            $0.sharedContoID == sharedID && $0.name == "Alimentari"
        })
        original.color = "#4CAF50"; original.icon = "heart"; original.kind = nil
        let originalParent = original.parentCategoryId
        let root = try #require(context.fetch(FetchDescriptor<FinanceCore.Category>()).first { $0.id == originalParent })
        root.kind = nil
        let other = Conto(name: "Viaggi", type: .checking); other.account = conto.account; other.usesSharedCategories = true
        let otherCategory = FinanceCore.Category(name: "Trasporti"); otherCategory.account = conto.account; otherCategory.sharedContoID = other.id
        context.insert(other); context.insert(otherCategory); try context.save()
        let before = try context.fetch(FetchDescriptor<FinanceCore.Category>())
        let plan = try CategoryDefaults(context: context).upgrade(conto)
        #expect(plan.addedCount > 0)
        #expect(CategoryDefaults.plan(for: conto).isEmpty)
        #expect(try CategoryDefaults(context: context).upgrade(conto).isEmpty)
        #expect(original.color == "#4CAF50" && original.icon == "heart" && original.kind == nil && original.parentCategoryId == originalParent)
        let after = try context.fetch(FetchDescriptor<FinanceCore.Category>())
        let oldIDs = Set(before.map(\.id))
        let created = after.filter { !oldIDs.contains($0.id) }
        #expect(created.count == plan.addedCount && created.allSatisfy { $0.sharedContoID == sharedID })
        #expect(created.contains { $0.parentCategoryId != nil })
        #expect(root.kind == nil && created.filter { $0.parentCategoryId == root.id }.allSatisfy { $0.kind == nil })
        #expect(after.filter { $0.sharedContoID == other.id }.count == 1)
        #expect(try context.fetch(FetchDescriptor<Budget>()).first?.categories?.first?.id == personalCategoryID)
        let exported = try SharedBookParticipantExporter.export(scope: scope, container: container)
        #expect(exported.records.filter { $0.id.kind == .category }.count == after.filter { $0.sharedContoID == sharedID }.count)
    }

    @Test func sharedSuggestionKeysSurviveImportWithoutResurrectingArchivedDefaults() throws {
        let (owner, scope, sharedID, _, _, _) = try fixture()
        let context = owner.mainContext
        let conto = try #require(context.fetch(FetchDescriptor<Conto>()).first { $0.id == sharedID })
        try CategoryDefaults(context: context).upgrade(conto)
        let archived = try #require(context.fetch(FetchDescriptor<FinanceCore.Category>()).first {
            $0.sharedContoID == sharedID && $0.externalID.hasPrefix("formi.shared-category-default:") && $0.parentCategoryId != nil
        })
        archived.isActive = false; try context.save()
        #expect(CategoryDefaults.plan(for: conto).isEmpty)
        let snapshot = try SharedBookParticipantExporter.export(scope: scope, container: owner)
        let receiver = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        try SharedBookImporter.apply(scope: scope, records: snapshot.records, assets: snapshot.assets, container: receiver)
        let received = try #require(receiver.mainContext.fetch(FetchDescriptor<Conto>()).first)
        let count = try receiver.mainContext.fetchCount(FetchDescriptor<FinanceCore.Category>())
        #expect(received.id != sharedID)
        #expect(try CategoryDefaults(context: receiver.mainContext).upgrade(received).isEmpty)
        #expect(try receiver.mainContext.fetchCount(FetchDescriptor<FinanceCore.Category>()) == count)
        #expect(try receiver.mainContext.fetch(FetchDescriptor<FinanceCore.Category>()).first { $0.externalID == archived.externalID }?.isActive == false)
    }

    @Test func sharedSuggestionFailureRollsBackOnlyItsCreationsAndRejectsPrivateConti() throws {
        struct SaveFailure: Error {}
        let (container, _, sharedID, personalID, _, _) = try fixture()
        let context = container.mainContext
        let conti = try context.fetch(FetchDescriptor<Conto>())
        let shared = try #require(conti.first { $0.id == sharedID })
        let personal = try #require(conti.first { $0.id == personalID })
        let before = try context.fetchCount(FetchDescriptor<FinanceCore.Category>())
        personal.name = "Modifica in corso"
        let edits = CategoryDefaults(context: context, save: { throw SaveFailure() })
        #expect(throws: SaveFailure.self) { try edits.upgrade(shared) }
        #expect(throws: CategoryDefaults.Failure.self) { try edits.upgrade(personal) }
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<FinanceCore.Category>()) == before)
        #expect(personal.name == "Modifica in corso")
    }

    @Test func selectedSuggestionsAddOnlyChosenChildAndRequiredParentWithoutDuplicates() throws {
        let (container, _, sharedID, _, _, _) = try fixture()
        let context = container.mainContext
        let conto = try #require(context.fetch(FetchDescriptor<Conto>()).first { $0.id == sharedID })
        let before = try context.fetch(FetchDescriptor<FinanceCore.Category>())
        let oldIDs = Set(before.map(\.id))
        let defaults = CategoryDefaults(context: context)
        let result = try defaults.addSuggestions(["carburante"], to: conto)
        #expect(result.addedCount == 2)
        let added = try context.fetch(FetchDescriptor<FinanceCore.Category>()).filter { !oldIDs.contains($0.id) }
        let parent = try #require(added.first { $0.name == "Trasporti" })
        let child = try #require(added.first { $0.name == "Carburante" })
        #expect(added.count == 2 && added.allSatisfy { $0.sharedContoID == sharedID })
        #expect(child.parentCategoryId == parent.id)
        #expect(try defaults.addSuggestions(["carburante"], to: conto).addedCount == 0)
        child.isActive = false; try context.save()
        #expect(try defaults.addSuggestions(["carburante"], to: conto).addedCount == 0)
        #expect(child.isActive == false)
        #expect(try defaults.addSuggestions(["salute"], to: conto).addedCount == 1)
        #expect(try context.fetch(FetchDescriptor<FinanceCore.Category>()).filter { $0.sharedContoID == nil }.count == before.filter { $0.sharedContoID == nil }.count)
    }

    @Test func selectedPersonalSuggestionsPreserveExistingParentAndStayOutsideSharedPool() throws {
        let (container, _, sharedID, _, _, _) = try fixture()
        let context = container.mainContext
        let conto = try #require(context.fetch(FetchDescriptor<Conto>()).first { $0.id == sharedID })
        let book = try #require(conto.account)
        let root = FinanceCore.Category(name: "Trasporti", color: "#4CAF50", icon: "heart", kind: nil)
        root.account = book; context.insert(root); try context.save()
        let sharedBefore = Set(try context.fetch(FetchDescriptor<FinanceCore.Category>()).filter { $0.sharedContoID == sharedID }.map(\.id))
        let result = try CategoryDefaults(context: context).addSuggestions(["carburante"], to: book)
        #expect(result.addedCount == 1)
        let child = try #require(context.fetch(FetchDescriptor<FinanceCore.Category>()).first { $0.name == "Carburante" })
        #expect(child.sharedContoID == nil && child.parentCategoryId == root.id && child.kind == nil)
        #expect(root.color == "#4CAF50" && root.icon == "heart" && root.kind == nil)
        #expect(Set(try context.fetch(FetchDescriptor<FinanceCore.Category>()).filter { $0.sharedContoID == sharedID }.map(\.id)) == sharedBefore)
    }

    @Test func selectedSuggestionValidationAndSaveFailureLeaveNoPartialTree() throws {
        struct SaveFailure: Error {}
        let (container, _, sharedID, personalID, _, _) = try fixture()
        let context = container.mainContext
        let conti = try context.fetch(FetchDescriptor<Conto>())
        let conto = try #require(conti.first { $0.id == sharedID })
        let personal = try #require(conti.first { $0.id == personalID })
        let before = try context.fetchCount(FetchDescriptor<FinanceCore.Category>())
        let defaults = CategoryDefaults(context: context)
        #expect(throws: CategoryDefaults.Failure.self) { try defaults.addSuggestions([], to: conto) }
        #expect(throws: CategoryDefaults.Failure.self) { try defaults.addSuggestions(["carburante", "invalid"], to: conto) }
        #expect(throws: CategoryDefaults.Failure.self) { try defaults.addSuggestions(["carburante"], to: personal) }
        personal.name = "Bozza privata"
        let failing = CategoryDefaults(context: context, save: { throw SaveFailure() })
        #expect(throws: SaveFailure.self) { try failing.addSuggestions(["carburante"], to: conto) }
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<FinanceCore.Category>()) == before)
        #expect(personal.name == "Bozza privata")
    }

    @Test func selectingAnExistingFlatSuggestionDoesNotCreateAnUnneededParent() throws {
        let (container, _, sharedID, _, _, _) = try fixture()
        let context = container.mainContext
        let conto = try #require(context.fetch(FetchDescriptor<Conto>()).first { $0.id == sharedID })
        let book = try #require(conto.account)
        let before = try context.fetchCount(FetchDescriptor<FinanceCore.Category>())
        #expect(try CategoryDefaults(context: context).addSuggestions(["alimentari"], to: book).addedCount == 0)
        #expect(try context.fetchCount(FetchDescriptor<FinanceCore.Category>()) == before)
    }

}
