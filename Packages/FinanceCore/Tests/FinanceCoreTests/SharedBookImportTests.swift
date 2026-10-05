import Foundation
import SwiftData
import Testing
@testable import FinanceCore

@MainActor
struct SharedBookImportTests {
    private func fixture() throws -> (SharedBookScope, SharedBookExport) {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let context = container.mainContext
        let book = Account(name: "Casa", currency: "EUR")
        let conto = Conto(name: "Comune", type: .checking, initialBalance: 1000)
        conto.account = book; book.conti = [conto]
        let category = FinanceCore.Category(name: "Cibo")
        category.account = book; book.categories = [category]
        let expense = Transaction(amount: 40, type: .expense, transactionDescription: "Cena")
        expense.setFromConto(conto); expense.setCategory(category)
        expense.originalAmount = 44; expense.originalCurrency = "USD"
        expense.attachments = [TransactionAttachment(filename: "ricevuta.pdf", contentType: "com.adobe.pdf", data: Data([1, 2, 3]))]
        let budget = Budget(name: "Cibo", amount: 100, period: .monthly)
        budget.account = book; budget.categories = [category]; book.budgets = [budget]
        context.insert(book); context.insert(expense); context.insert(budget)
        context.insert(RecurrenceResolution(sourceID: expense.id, scheduledDate: expense.date.addingTimeInterval(86400), isSkipped: true))
        try context.save()
        return (SharedBookScope(ownerName: "owner-A", bookID: book.id), try SharedBookExporter.export(bookID: book.id, container: container))
    }

    @Test func repeatedImportPreservesRelationshipsAssetsAndLocalIdentity() throws {
        let (scope, snapshot) = try fixture()
        let target = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let first = try SharedBookImporter.apply(scope: scope, records: snapshot.records.reversed(), assets: snapshot.assets, container: target)
        let second = try SharedBookImporter.apply(scope: scope, records: snapshot.records, assets: snapshot.assets, container: target)
        #expect(first == second && first != scope.bookID)
        let context = ModelContext(target)
        #expect(try context.fetchCount(FetchDescriptor<Account>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<SharedBookMembership>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<SharedBookRecordLink>()) == snapshot.records.count)
        let expense = try #require(context.fetch(FetchDescriptor<Transaction>()).first)
        #expect(expense.amount == 40 && expense.originalAmount == 44 && expense.originalCurrency == "USD")
        #expect(expense.fromConto?.account?.id == first)
        #expect(expense.category?.account?.id == first)
        #expect(expense.attachments?.first?.data == Data([1, 2, 3]))
        let budget = try #require(context.fetch(FetchDescriptor<Budget>()).first)
        #expect(budget.categories?.first?.id == expense.category?.id)
        let resolution = try #require(context.fetch(FetchDescriptor<RecurrenceResolution>()).first)
        #expect(resolution.sourceID == expense.id && resolution.isSkipped)
        #expect(resolution.key == RecurrenceResolution.key(sourceID: expense.id, date: resolution.scheduledDate))
    }

    @Test func ownersAreIsolatedFromEachOtherAndExistingPrivateUUIDs() throws {
        let (scope, snapshot) = try fixture()
        let target = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let privateBook = Account(name: "Privato", currency: "USD"); privateBook.id = scope.bookID
        target.mainContext.insert(privateBook); try target.mainContext.save()
        let first = try SharedBookImporter.apply(scope: scope, records: snapshot.records, assets: snapshot.assets, container: target)
        let other = SharedBookScope(ownerName: "owner-B", bookID: scope.bookID)
        let second = try SharedBookImporter.apply(scope: other, records: snapshot.records, assets: snapshot.assets, container: target)
        #expect(first != second)
        let books = try ModelContext(target).fetch(FetchDescriptor<Account>())
        #expect(books.count == 3)
        #expect(books.first { $0.id == scope.bookID }?.name == "Privato")
    }

    @Test func malformedFieldRollsBackAllocatedGraphAndMetadata() throws {
        let (scope, snapshot) = try fixture()
        let target = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        var records = snapshot.records
        let index = try #require(records.firstIndex { $0.id.kind == .transaction })
        records[index].fields["amount"] = .text("invalid")
        #expect(throws: (any Error).self) { try SharedBookImporter.apply(scope: scope, records: records, assets: snapshot.assets, container: target) }
        let context = ModelContext(target)
        #expect(try context.fetchCount(FetchDescriptor<Account>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Transaction>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<SharedBookMembership>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<SharedBookRecordLink>()) == 0)
        #expect(throws: (any Error).self) { try SharedBookImporter.apply(scope: scope, records: snapshot.records, assets: [:], container: target) }
    }

    @Test func deletionRequiresReconciliationOfLocalChildren() throws {
        let (scope, snapshot) = try fixture()
        let target = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        try SharedBookImporter.apply(scope: scope, records: snapshot.records, assets: snapshot.assets, container: target)
        let context = ModelContext(target)
        let expense = try #require(context.fetch(FetchDescriptor<Transaction>()).first)
        let newAttachment = TransactionAttachment(filename: "locale.pdf", contentType: "com.adobe.pdf", data: Data([4]))
        newAttachment.transaction = expense; context.insert(newAttachment); try context.save()
        let deletion = snapshot.records.map { [.transaction, .attachment, .recurrence].contains($0.id.kind) ? $0.tombstone() : $0 }
        #expect(throws: (any Error).self) { try SharedBookImporter.apply(scope: scope, records: deletion, assets: [:], container: target) }
        #expect(try ModelContext(target).fetchCount(FetchDescriptor<Transaction>()) == 1)
        context.delete(newAttachment); try context.save()
        try SharedBookImporter.apply(scope: scope, records: deletion, assets: [:], container: target)
        let fresh = ModelContext(target)
        #expect(try fresh.fetchCount(FetchDescriptor<Transaction>()) == 0)
        #expect(try fresh.fetchCount(FetchDescriptor<TransactionAttachment>()) == 0)
        #expect(try fresh.fetchCount(FetchDescriptor<RecurrenceResolution>()) == 0)
        #expect(try fresh.fetchCount(FetchDescriptor<Conto>()) == 1)
    }

    @Test func editsUpdateExistingRecordsAndOmissionIsNotDeletion() throws {
        let (scope, snapshot) = try fixture()
        let target = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        try SharedBookImporter.apply(scope: scope, records: snapshot.records, assets: snapshot.assets, container: target)
        var records = snapshot.records.filter { $0.id.kind != .budget }
        let index = try #require(records.firstIndex { $0.id.kind == .transaction })
        records[index].fields["amount"] = .decimal(65)
        records[index].fields["notes"] = .text("Aggiornata")
        try SharedBookImporter.apply(scope: scope, records: records, assets: snapshot.assets, container: target)
        let context = ModelContext(target)
        let expenses = try context.fetch(FetchDescriptor<Transaction>())
        #expect(expenses.count == 1 && expenses.first?.amount == 65 && expenses.first?.notes == "Aggiornata")
        #expect(try context.fetchCount(FetchDescriptor<Budget>()) == 1)
    }

    @Test func categoryCyclesAndForeignReferencesAreRejectedBeforeWriting() throws {
        let (scope, snapshot) = try fixture()
        let target = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        var records = snapshot.records
        let index = try #require(records.firstIndex { $0.id.kind == .category })
        records[index].fields["parent"] = .reference(records[index].id)
        #expect(throws: (any Error).self) { try SharedBookImporter.apply(scope: scope, records: records, assets: snapshot.assets, container: target) }
        records[index].fields["parent"] = .reference(SharedRecordID(bookID: UUID(), kind: .category, entityID: UUID().uuidString.lowercased()))
        #expect(throws: (any Error).self) { try SharedBookImporter.apply(scope: scope, records: records, assets: snapshot.assets, container: target) }
        #expect(try ModelContext(target).fetchCount(FetchDescriptor<Account>()) == 0)
    }

    @Test func participantRoundTripRestoresOriginalRecordAndAssetIdentities() throws {
        let (scope, snapshot) = try fixture()
        let target = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        try SharedBookImporter.apply(scope: scope, records: snapshot.records, assets: snapshot.assets, container: target)
        let outgoing = try SharedBookParticipantExporter.export(scope: scope, container: target)
        #expect(outgoing.bookID == scope.bookID)
        #expect(outgoing.records == snapshot.records)
        #expect(outgoing.assets == snapshot.assets)
        #expect(try ModelContext(target).fetchCount(FetchDescriptor<SharedBookRecordLink>()) == snapshot.records.count)
    }

    @Test func participantNewExpenseAndResolutionKeepIdentityAcrossRetriesAndImport() throws {
        let (scope, snapshot) = try fixture()
        let target = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        try SharedBookImporter.apply(scope: scope, records: snapshot.records, assets: snapshot.assets, container: target)
        let context = ModelContext(target)
        let source = try #require(context.fetch(FetchDescriptor<Transaction>()).first)
        let expense = Transaction(amount: 12, type: .expense)
        expense.setFromConto(source.fromConto); expense.setCategory(source.category)
        expense.recurrenceSourceID = source.id
        context.insert(expense)
        let scheduled = source.date.addingTimeInterval(172800)
        context.insert(RecurrenceResolution(sourceID: source.id, scheduledDate: scheduled, transactionID: expense.id))
        try context.save()
        let first = try SharedBookParticipantExporter.export(scope: scope, container: target)
        let second = try SharedBookParticipantExporter.export(scope: scope, container: target)
        #expect(first.records == second.records)
        let remoteSource = try #require(snapshot.records.first { $0.id.kind == .transaction })
        let remoteResolution = try #require(first.records.first { $0.id.kind == .recurrence && $0.fields["scheduledDate"] == .date(scheduled) })
        #expect(remoteResolution.fields["source"] == .reference(remoteSource.id))
        #expect(remoteResolution.id.entityID == RecurrenceResolution.key(sourceID: try #require(UUID(uuidString: remoteSource.id.entityID)), date: scheduled))
        try SharedBookImporter.apply(scope: scope, records: first.records, assets: first.assets, container: target)
        #expect(try ModelContext(target).fetchCount(FetchDescriptor<Transaction>()) == 2)
        #expect(try ModelContext(target).fetchCount(FetchDescriptor<RecurrenceResolution>()) == 2)
        let thirdDevice = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        try SharedBookImporter.apply(scope: scope, records: first.records, assets: first.assets, container: thirdDevice)
        let forwarded = try SharedBookParticipantExporter.export(scope: scope, container: thirdDevice)
        #expect(forwarded.records == first.records)
    }

    @Test func participantDeletionUsesOriginalRemoteIdentityAndRetainsAlias() throws {
        let (scope, snapshot) = try fixture()
        let target = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        try SharedBookImporter.apply(scope: scope, records: snapshot.records, assets: snapshot.assets, container: target)
        let context = ModelContext(target)
        let budget = try #require(context.fetch(FetchDescriptor<Budget>()).first)
        context.delete(budget); try context.save()
        let outgoing = try SharedBookParticipantExporter.export(scope: scope, container: target)
        let changes = try SharedBookMerge.localChanges(base: snapshot.records, completeLocal: outgoing.records)
        let original = try #require(snapshot.records.first { $0.id.kind == .budget })
        #expect(changes == [original.tombstone()])
        #expect(try ModelContext(target).fetchCount(FetchDescriptor<SharedBookRecordLink>()) == snapshot.records.count)
    }

    @Test func inconsistentAliasesAndUnregisteredScopesCannotBeExported() throws {
        let (scope, snapshot) = try fixture()
        let target = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        #expect(throws: (any Error).self) { try SharedBookParticipantExporter.export(scope: scope, container: target) }
        try SharedBookImporter.apply(scope: scope, records: snapshot.records, assets: snapshot.assets, container: target)
        let context = ModelContext(target)
        let link = try #require(context.fetch(FetchDescriptor<SharedBookRecordLink>()).first { $0.remoteRecordName.hasPrefix("transaction:") })
        context.insert(SharedBookRecordLink(scopeKey: scope.key, remoteRecordName: "transaction:\(UUID().uuidString.lowercased())", localIdentity: link.localIdentity))
        try context.save()
        let count = try context.fetchCount(FetchDescriptor<SharedBookRecordLink>())
        #expect(throws: (any Error).self) { try SharedBookParticipantExporter.export(scope: scope, container: target) }
        #expect(try ModelContext(target).fetchCount(FetchDescriptor<SharedBookRecordLink>()) == count)
    }
}
