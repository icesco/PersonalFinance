import Foundation
import SwiftData
import CloudKit
import Testing
@testable import FinanceCore

@MainActor
struct SharedContoTests {
    private let anna = TransactionPerson(id: "anna", name: "Anna")
    private let marco = TransactionPerson(id: "marco", name: "Marco")

    private func fixture() throws -> (ModelContainer, Account, Conto, Conto, Transaction, SharedBookScope) {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let book = Account(name: "Libro segreto", currency: "EUR")
        let personal = Conto(name: "Banca privata", type: .checking, initialBalance: 1000)
        let house = Conto(name: "Casa", type: .checking, initialBalance: 50)
        personal.account = book; house.account = book; book.conti = [personal, house]
        container.mainContext.insert(book)
        let transfer = Transaction.createTransfer(amount: 500, fromConto: personal, toConto: house,
            transactionDescription: "Banca privata verso Casa", notes: "Informazioni riservate")
        transfer.createdByJSON = marco.encoded; transfer.lastEditedByJSON = marco.encoded
        transfer.contributor = marco; transfer.assignedTo = anna
        transfer.placeName = "Luogo riservato"; transfer.originalCurrency = "USD"; transfer.originalAmount = 600
        transfer.attachments = [TransactionAttachment(filename: "privato.pdf", contentType: "com.adobe.pdf", data: Data([1, 2]))]
        container.mainContext.insert(transfer)
        let privateCategory = FinanceCore.Category(name: "Visita privata"); privateCategory.account = book
        container.mainContext.insert(privateCategory)
        let privateExpense = Transaction(amount: 70, type: .expense); privateExpense.setFromConto(personal); privateExpense.setCategory(privateCategory)
        container.mainContext.insert(privateExpense)
        let budget = Budget(name: "Budget privato", amount: 100, period: .monthly); budget.account = book
        container.mainContext.insert(budget)
        try container.mainContext.save()
        let scope = try SharedBookOwnerRegistration.register(bookID: book.id, contoID: house.id, ownerRecordName: "owner", container: container)
        return (container, book, personal, house, transfer, scope)
    }

    @Test func onlyTheSelectedContoAndSafeTransferProjectionAreExported() throws {
        let (container, book, personal, house, transfer, scope) = try fixture()
        let snapshot = try SharedBookParticipantExporter.export(scope: scope, container: container)
        #expect(scope.bookID == house.id && scope.bookID != book.id)
        #expect(snapshot.records.filter { $0.id.kind == .conto }.map(\.id.entityID) == [house.id.uuidString.lowercased()])
        #expect(!snapshot.records.contains { [.category, .budget, .goal, .attachment].contains($0.id.kind) })
        #expect(snapshot.assets.isEmpty)
        let record = try #require(snapshot.records.first { $0.id.kind == .transaction })
        #expect(record.id.entityID == transfer.id.uuidString.lowercased())
        #expect(record.fields["fromConto"] == nil && record.fields["toConto"] != nil)
        for key in ["notes", "originalAmount", "originalCurrency", "placeName", "destinationAmount"] { #expect(record.fields[key] == nil) }
        let payload = String(decoding: try JSONEncoder().encode(snapshot.records), as: UTF8.self)
        #expect(!payload.contains("Libro segreto") && !payload.contains("Banca privata") && !payload.contains("Visita privata"))
        #expect(!payload.contains(personal.id.uuidString.lowercased()))
        #expect(record.fields["contributor"] == .text(marco.encoded!))
        #expect(record.fields["assignedTo"] == .text(anna.encoded!))
    }

    @Test func participantRoundTripDoesNotDuplicateOrModifyPrivateGraph() throws {
        let (owner, book, personal, house, transfer, scope) = try fixture()
        let snapshot = try SharedBookParticipantExporter.export(scope: scope, container: owner)
        let target = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        try SharedBookImporter.apply(scope: scope, records: snapshot.records, assets: snapshot.assets, container: target)
        let returned = try SharedBookParticipantExporter.export(scope: scope, container: target)
        #expect(snapshot.records == returned.records)
        try SharedBookImporter.apply(scope: scope, records: returned.records, assets: returned.assets, container: owner)
        let context = ModelContext(owner)
        let saved = try #require(context.fetch(FetchDescriptor<Transaction>()).first { $0.id == transfer.id })
        #expect(saved.fromConto?.id == personal.id && saved.toConto?.id == house.id)
        #expect(saved.notes == "Informazioni riservate" && saved.attachments?.count == 1)
        #expect(try context.fetchCount(FetchDescriptor<Transaction>()) == 2)
        #expect(try context.fetch(FetchDescriptor<Account>()).first?.name == book.name)
    }

    @Test func remoteCorrectionAndDeletionKeepThePrivateTransferLinked() throws {
        let (owner, _, personal, house, transfer, scope) = try fixture()
        var snapshot = try SharedBookParticipantExporter.export(scope: scope, container: owner)
        var records = snapshot.records
        let index = try #require(records.firstIndex { $0.id.kind == .transaction })
        records[index].fields["amount"] = .decimal(550)
        records[index].fields["lastEditedBy"] = .text(anna.encoded!)
        records[index].fields["contributor"] = .text(marco.encoded!)
        try SharedBookImporter.apply(scope: scope, records: records, assets: [:], container: owner)
        let context = ModelContext(owner)
        let saved = try #require(context.fetch(FetchDescriptor<Transaction>()).first { $0.id == transfer.id })
        #expect(saved.amount == 550 && saved.fromConto?.id == personal.id && saved.toConto?.id == house.id)
        #expect(saved.notes == "Informazioni riservate" && saved.lastEditedBy == anna && saved.createdBy == marco)
        #expect(saved.fromConto?.balance == 380 && saved.toConto?.balance == 600)
        snapshot = try SharedBookParticipantExporter.export(scope: scope, container: owner)
        records = snapshot.records.map { $0.id.kind == .transaction ? $0.tombstone() : $0 }
        // Attachments of a private transfer were never exported; deleting the linked transfer deletes its local attachment as well.
        try SharedBookImporter.apply(scope: scope, records: records, assets: [:], container: owner)
        let after = ModelContext(owner)
        #expect(try after.fetchCount(FetchDescriptor<Transaction>()) == 1)
        #expect(try after.fetchCount(FetchDescriptor<TransactionAttachment>()) == 0)
    }

    @Test func crossCurrencyTransferSharesOnlyCreditedCurrencyAndPreservesPrivateDebit() throws {
        let (owner, _, _, _, transfer, scope) = try fixture()
        transfer.destinationAmount = 450; try owner.mainContext.save()
        var records = try SharedBookParticipantExporter.export(scope: scope, container: owner).records
        let index = try #require(records.firstIndex { $0.id.kind == .transaction })
        #expect(records[index].fields["amount"] == .decimal(450))
        records[index].fields["amount"] = .decimal(460)
        try SharedBookImporter.apply(scope: scope, records: records, assets: [:], container: owner)
        let saved = try #require(ModelContext(owner).fetch(FetchDescriptor<Transaction>()).first { $0.id == transfer.id })
        #expect(saved.amount == 500 && saved.destinationAmount == 460)
    }

    @Test func receivedContoCanJoinPrivateBookAndExportStillHasOnlyOneConto() throws {
        let (owner, _, _, _, _, scope) = try fixture()
        let snapshot = try SharedBookParticipantExporter.export(scope: scope, container: owner)
        let target = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        try SharedBookImporter.apply(scope: scope, records: snapshot.records, assets: [:], container: target)
        let privateBook = Account(name: "Il mio libro", currency: "EUR")
        let personal = Conto(name: "Privato di Anna", type: .checking, initialBalance: 800); personal.account = privateBook
        target.mainContext.insert(privateBook); target.mainContext.insert(personal); try target.mainContext.save()
        try SharedContoPlacement.move(scope: scope, to: privateBook.id, container: target)
        let returned = try SharedBookParticipantExporter.export(scope: scope, container: target)
        #expect(returned.records == snapshot.records)
        try SharedBookImporter.apply(scope: scope, records: snapshot.records, assets: [:], container: target)
        let context = ModelContext(target)
        let membership = try #require(context.fetch(FetchDescriptor<SharedBookMembership>()).first)
        #expect(membership.localBookID == privateBook.id)
        let conti = try context.fetch(FetchDescriptor<Conto>())
        #expect(conti.filter { $0.account?.id == privateBook.id }.count == 2)
        #expect(try context.fetch(FetchDescriptor<Account>()).first { $0.id == privateBook.id }?.name == "Il mio libro")
        #expect(throws: (any Error).self) { try SharedBookOwnerRegistration.register(bookID: privateBook.id, ownerRecordName: "anna", container: target) }
    }

    @Test func contributorsAreIndependentFromAuthorsAndFutureEntriesAreExcluded() throws {
        let (container, _, _, house, transfer, _) = try fixture()
        let now = Date(); let interval = DateInterval(start: now.addingTimeInterval(-86400), end: now.addingTimeInterval(86400))
        transfer.createdByJSON = anna.encoded; transfer.contributor = marco
        let unknown = Transaction(amount: 20, type: .transfer, date: now); unknown.setToConto(house); unknown.createdByJSON = anna.encoded
        let future = Transaction(amount: 1000, type: .transfer, date: now.addingTimeInterval(3600)); future.setToConto(house); future.contributor = anna
        let expense = Transaction(amount: 30, type: .expense, date: now); expense.setFromConto(house)
        let income = Transaction(amount: 80, type: .income, date: now); income.setToConto(house)
        for transaction in [unknown, future, expense, income] { container.mainContext.insert(transaction) }
        try container.mainContext.save()
        let rows = AccountContributions.summarize(conto: house, interval: interval, now: now)
        #expect(rows.count == 2)
        #expect(rows.first { $0.person?.id == marco.id }?.amount == 500)
        #expect(rows.first { $0.person == nil }?.amount == 20)
    }

    @Test func sharingMultipleContiIsAllowedButWholeBookOverlapIsRejected() throws {
        let (container, book, personal, house, _, scope) = try fixture()
        #expect(throws: (any Error).self) { try SharedBookOwnerRegistration.register(bookID: book.id, ownerRecordName: "owner", container: container) }
        let other = try SharedBookOwnerRegistration.register(bookID: book.id, contoID: personal.id, ownerRecordName: "owner", container: container)
        #expect(other.key != scope.key)
        _ = try SharedBookOwnerRegistration.register(bookID: book.id, contoID: house.id, ownerRecordName: "owner", container: container)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<SharedBookMembership>()) == 2)
    }
    @Test func aSharedContoScopeCannotBeWidenedOrRedirectAPrivateLeg() throws {
        let (owner, _, _, _, _, scope) = try fixture()
        let snapshot = try SharedBookParticipantExporter.export(scope: scope, container: owner)
        var records = snapshot.records
        let rootIndex = try #require(records.firstIndex { $0.id.kind == .book })
        records[rootIndex].fields["shareKind"] = nil; records[rootIndex].fields["sharedConto"] = nil
        #expect(throws: (any Error).self) { try SharedBookImporter.apply(scope: scope, records: records, assets: [:], container: owner) }
        records = snapshot.records
        let contoRecord = try #require(records.first { $0.id.kind == .conto })
        let extraID = SharedRecordID(bookID: scope.bookID, kind: .conto, entityID: UUID().uuidString.lowercased())
        records.append(SharedBookRecord(id: extraID, fields: contoRecord.fields))
        #expect(throws: (any Error).self) { try SharedBookImporter.apply(scope: scope, records: records, assets: [:], container: owner) }
        records = snapshot.records
        let transferIndex = try #require(records.firstIndex { $0.id.kind == .transaction })
        records[transferIndex].fields["fromConto"] = records[transferIndex].fields["toConto"]
        records[transferIndex].fields["toConto"] = nil
        #expect(throws: (any Error).self) { try SharedBookImporter.apply(scope: scope, records: records, assets: [:], container: owner) }
    }

    @Test func malformedAttributionRollsBackFinancialChanges() throws {
        let (owner, _, _, _, transfer, scope) = try fixture()
        var records = try SharedBookParticipantExporter.export(scope: scope, container: owner).records
        let index = try #require(records.firstIndex { $0.id.kind == .transaction })
        records[index].fields["amount"] = .decimal(800)
        records[index].fields["assignedTo"] = .text("invalid JSON")
        #expect(throws: (any Error).self) { try SharedBookImporter.apply(scope: scope, records: records, assets: [:], container: owner) }
        let saved = try #require(ModelContext(owner).fetch(FetchDescriptor<Transaction>()).first { $0.id == transfer.id })
        #expect(saved.amount == 500 && saved.assignedTo == anna)
    }

    @Test func leavingAfterPlacementRejoinsWithFreshIdentityAndKeepsPrivateCopies() throws {
        let (owner, _, _, _, _, scope) = try fixture()
        let snapshot = try SharedBookParticipantExporter.export(scope: scope, container: owner)
        let target = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        try SharedBookImporter.apply(scope: scope, records: snapshot.records, assets: [:], container: target)
        let privateBook = Account(name: "Personale", currency: "EUR")
        target.mainContext.insert(privateBook); try target.mainContext.save()
        try SharedContoPlacement.move(scope: scope, to: privateBook.id, container: target)
        let before = try #require(ModelContext(target).fetch(FetchDescriptor<SharedBookMembership>()).first?.localContoID)
        // Simulate a server-acknowledged departure, then a new accepted invitation.
        try SharedBookDepartureService.preservePrivateCopy(scope: scope, container: target)
        try SharedBookImporter.apply(scope: scope, records: snapshot.records, assets: [:], container: target)
        let context = ModelContext(target)
        let after = try #require(context.fetch(FetchDescriptor<SharedBookMembership>()).first?.localContoID)
        #expect(before != after)
        #expect(try context.fetchCount(FetchDescriptor<Conto>()) == 2)
        #expect(try context.fetch(FetchDescriptor<Conto>()).first { $0.id == before }?.account?.id == privateBook.id)
    }

    @Test func usedCategoriesAreSharedAndRetainedWhenTheirLastSharedExpenseIsDeleted() throws {
        let (owner, book, _, house, _, scope) = try fixture()
        let category = FinanceCore.Category(name: "Alimentari"); category.account = book
        owner.mainContext.insert(category)
        let expense = Transaction(amount: 35, type: .expense); expense.setFromConto(house); expense.setCategory(category)
        expense.createdByJSON = anna.encoded
        owner.mainContext.insert(expense); try owner.mainContext.save()
        let snapshot = try SharedBookParticipantExporter.export(scope: scope, container: owner)
        #expect(snapshot.records.contains { $0.id.kind == .category && $0.fields["name"] == .text("Alimentari") })
        let target = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        try SharedBookImporter.apply(scope: scope, records: snapshot.records, assets: [:], container: target)
        let returned = try SharedBookParticipantExporter.export(scope: scope, container: target)
        #expect(returned.records == snapshot.records)
        owner.mainContext.delete(expense); try owner.mainContext.save()
        let after = try SharedBookParticipantExporter.export(scope: scope, container: owner)
        #expect(after.records.contains { $0.id.kind == .category && $0.fields["name"] == .text("Alimentari") })
    }

    @Test func accountSharesHaveDistinctZonesKeysAndInvitationCompatibility() throws {
        let (owner, _, _, _, _, scope) = try fixture()
        let legacyScope = SharedBookScope(ownerName: scope.ownerName, bookID: scope.bookID)
        #expect(scope.isContoShare && scope.key != legacyScope.key)
        let zoneName = SharedBookCloudCodec.zoneName(bookID: scope.bookID, isContoShare: true)
        #expect(zoneName.hasPrefix("FormiConto-") && !zoneName.hasPrefix("ForgiaBook-"))
        let invitation = try SharedBookInvitation.scope(containerIdentifier: FinanceCoreModule.cloudKitContainerIdentifier,
            zoneName: zoneName, ownerName: scope.ownerName, shareRecordName: CKRecordNameZoneWideShare, hierarchical: false)
        #expect(invitation == scope)
        // A legacy client reconstructs a book scope: it cannot locate or export this membership.
        #expect(throws: (any Error).self) { try SharedBookParticipantExporter.export(scope: legacyScope, container: owner) }
        let snapshot = try SharedBookParticipantExporter.export(scope: scope, container: owner)
        #expect(throws: (any Error).self) { try SharedBookImporter.apply(scope: legacyScope, records: snapshot.records, assets: [:], container: owner) }
        let decoded = try JSONDecoder().decode(SharedBookScope.self, from: JSONEncoder().encode(scope))
        #expect(decoded == scope)
        let legacyData = Data("{\"ownerName\":\"owner\",\"bookID\":\"\(scope.bookID.uuidString)\"}".utf8)
        #expect(try !JSONDecoder().decode(SharedBookScope.self, from: legacyData).isContoShare)
    }

    @Test func acceptancePlacesContoInChosenBookAndRemovesOnlyEmptyReceptionBook() throws {
        let (owner, _, _, _, _, scope) = try fixture()
        let snapshot = try SharedBookParticipantExporter.export(scope: scope, container: owner)
        let target = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let receivedID = try SharedBookImporter.apply(scope: scope, records: snapshot.records, assets: [:], container: target)
        let personal = Account(name: "Il mio libro", currency: "EUR")
        target.mainContext.insert(personal); try target.mainContext.save()
        let before = try #require(ModelContext(target).fetch(FetchDescriptor<SharedBookMembership>()).first?.localContoID)
        let result = try SharedContoPlacement.completeAcceptance(scope: scope, destination: .existing(personal.id), container: target)
        let context = ModelContext(target)
        #expect(result == personal.id)
        #expect(try context.fetchCount(FetchDescriptor<Account>()) == 1)
        #expect(try !context.fetch(FetchDescriptor<Account>()).contains { $0.id == receivedID })
        #expect(try context.fetch(FetchDescriptor<SharedBookMembership>()).first?.localContoID == before)
        #expect(try SharedBookParticipantExporter.export(scope: scope, container: target).records == snapshot.records)
    }

    @Test func acceptanceCreatesNamedBookInSharedCurrencyWithoutDuplicatingConto() throws {
        let (owner, _, _, _, _, scope) = try fixture()
        let snapshot = try SharedBookParticipantExporter.export(scope: scope, container: owner)
        let target = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        try SharedBookImporter.apply(scope: scope, records: snapshot.records, assets: [:], container: target)
        let id = try SharedContoPlacement.completeAcceptance(scope: scope, destination: .newBook(name: "  Spese di casa  "), container: target)
        let context = ModelContext(target)
        let books = try context.fetch(FetchDescriptor<Account>())
        #expect(books.count == 1 && books.first?.id == id && books.first?.name == "Spese di casa" && books.first?.currency == "EUR")
        #expect(try context.fetchCount(FetchDescriptor<Conto>()) == 1)
        #expect(try SharedBookParticipantExporter.export(scope: scope, container: target).records == snapshot.records)
    }

    @Test func acceptancePreservesOtherDataAndFailedChoicesLeaveNoNewBook() throws {
        let (owner, _, _, _, _, scope) = try fixture()
        let snapshot = try SharedBookParticipantExporter.export(scope: scope, container: owner)
        let target = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let receptionID = try SharedBookImporter.apply(scope: scope, records: snapshot.records, assets: [:], container: target)
        let reception = try #require(target.mainContext.fetch(FetchDescriptor<Account>()).first)
        let added = Conto(name: "Aggiunto personalmente", type: .cash); added.account = reception
        let dollarBook = Account(name: "Dollari", currency: "USD")
        target.mainContext.insert(added); target.mainContext.insert(dollarBook); try target.mainContext.save()
        #expect(throws: (any Error).self) { try SharedContoPlacement.completeAcceptance(scope: scope, destination: .newBook(name: "   "), container: target) }
        #expect(throws: (any Error).self) { try SharedContoPlacement.completeAcceptance(scope: scope, destination: .existing(dollarBook.id), container: target) }
        #expect(try ModelContext(target).fetchCount(FetchDescriptor<Account>()) == 2)
        let result = try SharedContoPlacement.completeAcceptance(scope: scope, destination: .newBook(name: "Casa condivisa"), container: target)
        let context = ModelContext(target)
        #expect(try context.fetchCount(FetchDescriptor<Account>()) == 3)
        #expect(try context.fetch(FetchDescriptor<Conto>()).first { $0.id == added.id }?.account?.id == receptionID)
        #expect(try context.fetch(FetchDescriptor<SharedBookMembership>()).first?.localBookID == result)
    }

    @Test func budgetsStayPrivateForBothParticipants() throws {
        let (owner, _, _, _, _, scope) = try fixture()
        let snapshot = try SharedBookParticipantExporter.export(scope: scope, container: owner)
        #expect(!snapshot.records.contains { $0.id.kind == .budget })
        let receiver = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let bookID = try SharedBookImporter.apply(scope: scope, records: snapshot.records, assets: snapshot.assets, container: receiver)
        #expect(try ModelContext(receiver).fetchCount(FetchDescriptor<Budget>()) == 0)
        let context = receiver.mainContext
        let book = try #require(context.fetch(FetchDescriptor<Account>()).first { $0.id == bookID })
        let privateBudget = Budget(name: "Budget personale della destinataria", amount: 350, period: .monthly)
        privateBudget.account = book; context.insert(privateBudget); try context.save()
        let returned = try SharedBookParticipantExporter.export(scope: scope, container: receiver)
        #expect(!returned.records.contains { $0.id.kind == .budget })
        try SharedBookImporter.apply(scope: scope, records: returned.records, assets: returned.assets, container: owner)
        try SharedBookImporter.apply(scope: scope, records: snapshot.records, assets: snapshot.assets, container: receiver)
        #expect(try ModelContext(owner).fetchCount(FetchDescriptor<Budget>()) == 1)
        let retained = try ModelContext(receiver).fetch(FetchDescriptor<Budget>())
        #expect(retained.count == 1 && retained.first?.id == privateBudget.id && retained.first?.amount == 350)
    }

}
