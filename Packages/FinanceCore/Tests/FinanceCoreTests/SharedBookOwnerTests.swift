import Foundation
import SwiftData
import CloudKit
import Testing
@testable import FinanceCore

@MainActor
struct SharedBookOwnerTests {
    private func fixture() throws -> (ModelContainer, UUID, UUID, UUID) {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let book = Account(name: "Comune", currency: "EUR")
        let privateBook = Account(name: "Privato", currency: "EUR")
        let shared = Conto(name: "Comune", type: .checking, initialBalance: 100)
        let personal = Conto(name: "Privato", type: .checking, initialBalance: 500)
        shared.account = book; book.conti = [shared]
        personal.account = privateBook; privateBook.conti = [personal]
        let transfer = FinanceCore.Transaction(amount: 25, type: .transfer)
        transfer.setFromConto(personal); transfer.setToConto(shared)
        container.mainContext.insert(book); container.mainContext.insert(privateBook); container.mainContext.insert(transfer)
        try container.mainContext.save()
        return (container, book.id, personal.id, transfer.id)
    }

    @Test func registrationIsIdempotentAndOwnerKeepsOriginalBookAndTransferLegs() throws {
        let (container, bookID, personalID, transferID) = try fixture()
        let original = try SharedBookExporter.export(bookID: bookID, container: container)
        let scope = try SharedBookOwnerRegistration.register(bookID: bookID, ownerRecordName: "owner", container: container)
        #expect(try SharedBookOwnerRegistration.register(bookID: bookID, ownerRecordName: "owner", container: container) == scope)
        let outbound = try SharedBookParticipantExporter.export(scope: scope, container: container)
        #expect(outbound.records == original.records)
        #expect(try SharedBookImporter.apply(scope: scope, records: outbound.records, assets: outbound.assets, container: container) == bookID)
        let context = ModelContext(container)
        let transfer = try #require(context.fetch(FetchDescriptor<FinanceCore.Transaction>()).first { $0.id == transferID })
        #expect(transfer.fromConto?.id == personalID && transfer.toConto?.account?.id == bookID)
        #expect(transfer.amount == 25)
        #expect(try context.fetchCount(FetchDescriptor<Account>()) == 2)
        #expect(try context.fetchCount(FetchDescriptor<SharedBookMembership>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<SharedBookRecordLink>()) == original.records.count)
        #expect(try context.fetch(FetchDescriptor<SharedBookMembership>()).first?.isOwner == true)
    }

    @Test func changingSharedProjectionCannotChangePrivateTransferOrPartiallyApplyBook() throws {
        let (container, bookID, personalID, transferID) = try fixture()
        let scope = try SharedBookOwnerRegistration.register(bookID: bookID, ownerRecordName: "owner", container: container)
        let outbound = try SharedBookParticipantExporter.export(scope: scope, container: container)
        var modified = outbound.records
        for index in modified.indices {
            if modified[index].id.kind == .transaction { modified[index].fields["amount"] = .decimal(80) }
            if modified[index].id.kind == .book { modified[index].fields["name"] = .text("Non applicare") }
        }
        #expect(throws: (any Error).self) { try SharedBookImporter.apply(scope: scope, records: modified, assets: outbound.assets, container: container) }
        let context = ModelContext(container)
        let transfer = try #require(context.fetch(FetchDescriptor<FinanceCore.Transaction>()).first { $0.id == transferID })
        #expect(transfer.amount == 25 && transfer.fromConto?.id == personalID)
        #expect(try context.fetch(FetchDescriptor<Account>()).first { $0.id == bookID }?.name == "Comune")
    }

    @Test func changingOwnerOrRegisteringImportedBookIsRejected() throws {
        let (container, bookID, _, _) = try fixture()
        #expect(throws: (any Error).self) { try SharedBookOwnerRegistration.register(bookID: bookID, ownerRecordName: CKCurrentUserDefaultName, container: container) }
        let scope = try SharedBookOwnerRegistration.register(bookID: bookID, ownerRecordName: "owner", container: container)
        #expect(throws: (any Error).self) { try SharedBookOwnerRegistration.register(bookID: bookID, ownerRecordName: "other-owner", container: container) }
        let snapshot = try SharedBookExporter.export(bookID: bookID, container: container)
        let participant = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let importedID = try SharedBookImporter.apply(scope: scope, records: snapshot.records, assets: snapshot.assets, container: participant)
        #expect(throws: (any Error).self) { try SharedBookOwnerRegistration.register(bookID: importedID, ownerRecordName: "participant", container: participant) }
        #expect(try ModelContext(participant).fetchCount(FetchDescriptor<SharedBookMembership>()) == 1)
    }
}
