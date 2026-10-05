import Foundation
import SwiftData
import CloudKit
import Testing
@testable import FinanceCore

struct SharedBookMergeTests {
    private func record() -> SharedBookRecord {
        SharedBookRecord(id: SharedRecordID(bookID: UUID(), kind: .transaction, entityID: UUID().uuidString),
                         fields: ["amount": .decimal(40), "notes": .text("Pranzo"), "updatedAt": .date(Date(timeIntervalSince1970: 100))])
    }

    @Test func disjointEditsMergeWithoutLosingEitherChange() throws {
        let base = record()
        var local = base, remote = base
        local.fields["amount"] = .decimal(50)
        local.fields["updatedAt"] = .date(Date(timeIntervalSince1970: 101))
        remote.fields["notes"] = .text("Con amici")
        remote.fields["updatedAt"] = .date(Date(timeIntervalSince1970: 102))
        let result = try SharedBookMerge.merge(base: base, local: local, remote: remote)
        guard case let .merged(merged) = result else { Issue.record("Expected a merge"); return }
        #expect(merged.fields["amount"] == .decimal(50))
        #expect(merged.fields["notes"] == .text("Con amici"))
        #expect(merged.fields["updatedAt"] == remote.fields["updatedAt"])
    }

    @Test func concurrentAmountsAndDeletionRemainExplicitConflicts() throws {
        let base = record()
        var local = base, remote = base
        local.fields["amount"] = .decimal(50)
        remote.fields["amount"] = .decimal(60)
        remote.fields["notes"] = .text("Nota aggiornata dall’altra persona")
        guard case let .conflict(conflict) = try SharedBookMerge.merge(base: base, local: local, remote: remote) else {
            Issue.record("Concurrent amounts must not choose a winner"); return
        }
        #expect(conflict.reason == .fields(["amount"]))
        #expect(conflict.local == local && conflict.remote == remote)
        let resolved = try SharedBookMerge.resolveFields(conflict, choices: ["amount": .local])
        #expect(resolved.fields["amount"] == .decimal(50))
        #expect(resolved.fields["notes"] == remote.fields["notes"])
        #expect(throws: (any Error).self) { try SharedBookMerge.resolveFields(conflict, choices: [:]) }
        guard case let .conflict(deletion) = try SharedBookMerge.merge(base: base, local: local.tombstone(), remote: remote) else {
            Issue.record("Deletion must not silently discard a concurrent edit"); return
        }
        #expect(deletion.reason == .deletion)
        #expect(try SharedBookMerge.merge(base: base, local: base, remote: base.tombstone()) == .merged(base.tombstone()))
    }

    @Test func fieldRemovalAndMissingAncestorDoNotLoseData() throws {
        let base = record()
        var local = base, remote = base
        local.fields.removeValue(forKey: "notes")
        remote.fields["amount"] = .decimal(55)
        guard case let .merged(merged) = try SharedBookMerge.merge(base: base, local: local, remote: remote) else {
            Issue.record("Independent removal and edit should merge"); return
        }
        #expect(merged.fields["notes"] == nil)
        #expect(merged.fields["amount"] == .decimal(55))
        guard case let .conflict(conflict) = try SharedBookMerge.merge(base: nil, local: local, remote: remote) else {
            Issue.record("Without an ancestor, do not guess which fields are current"); return
        }
        #expect(conflict.reason == .concurrentCreation)
    }

    @Test func deletionDeltaIsExplicitAndCrossBookDiffIsRejected() throws {
        let base = record()
        #expect(try SharedBookMerge.localChanges(base: [base], completeLocal: []) == [base.tombstone()])
        #expect(try SharedBookMerge.localChanges(base: [base.tombstone()], completeLocal: []) == [])
        #expect(throws: (any Error).self) { try SharedBookMerge.localChanges(base: [base], completeLocal: [record()]) }
        var newer = base; newer.version = 2
        #expect(throws: (any Error).self) { try SharedBookMerge.merge(base: base, local: base, remote: newer) }
    }
}

@MainActor
struct SharedBookExportTests {
    @Test func exportsOnlySelectedBookAndKeepsAttachmentsOutsideRecordPayload() throws {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let context = container.mainContext
        let book = Account(name: "Condiviso", currency: "EUR")
        let privateBook = Account(name: "Segreto", currency: "USD")
        let conto = Conto(name: "Comune", type: .checking, initialBalance: 1000)
        let privateConto = Conto(name: "Privato", type: .checking, initialBalance: 2000)
        conto.account = book; privateConto.account = privateBook
        book.conti = [conto]; privateBook.conti = [privateConto]
        let category = FinanceCore.Category(name: "Cibo"); category.account = book; book.categories = [category]
        let expense = Transaction(amount: 40, type: .expense, transactionDescription: "Cena")
        expense.setFromConto(conto); expense.setCategory(category)
        let bytes = Data(repeating: 71, count: 2_000_000)
        expense.attachments = [TransactionAttachment(filename: "scontrino.pdf", contentType: "com.adobe.pdf", data: bytes)]
        let transfer = Transaction(amount: 10, type: .transfer)
        transfer.setFromConto(privateConto); transfer.setToConto(conto)
        transfer.destinationAmount = 9
        let privateExpense = Transaction(amount: 90, type: .expense, transactionDescription: "Non condividere")
        privateExpense.setFromConto(privateConto)
        // A stale destination left by an older edit must not expose an expense
        // whose actual source belongs to a different, private book.
        privateExpense.setToConto(conto)
        let budget = Budget(name: "Cibo", amount: 100, period: .monthly)
        budget.account = book; budget.categories = [category]; book.budgets = [budget]
        context.insert(book); context.insert(privateBook)
        context.insert(expense); context.insert(transfer); context.insert(privateExpense)
        context.insert(budget)
        try context.save()
        let export = try SharedBookExporter.export(bookID: book.id, container: container)
        #expect(export.records.allSatisfy { $0.id.bookID == book.id })
        #expect(!export.records.contains { $0.id.entityID == privateExpense.id.uuidString.lowercased() })
        let json = try JSONEncoder().encode(export.records)
        #expect(json.count < 20_000)
        #expect(!String(decoding: json, as: UTF8.self).contains("Segreto"))
        #expect(!String(decoding: json, as: UTF8.self).contains(privateConto.id.uuidString.lowercased()))
        #expect(export.assets.values.first == bytes)
        let sharedTransfer = try #require(export.records.first { $0.id.entityID == transfer.id.uuidString.lowercased() })
        #expect(sharedTransfer.fields["type"] == .text("transfer"))
        #expect(sharedTransfer.fields["fromConto"] == nil)
        #expect(sharedTransfer.fields["destinationAmount"] == .decimal(9))
        let asset = try #require(export.records.first { $0.id.kind == .attachment })
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try bytes.write(to: url)
        let zone = CKRecordZone.ID(zoneName: SharedBookCloudCodec.zoneName(bookID: book.id), ownerName: CKCurrentUserDefaultName)
        let cloud = try SharedBookCloudCodec.encode(asset, zoneID: zone, assetURL: url)
        #expect(try SharedBookCloudCodec.decode(cloud, expectedBookID: book.id) == asset)
        try Data([1, 2]).write(to: url)
        #expect(throws: (any Error).self) { try SharedBookCloudCodec.decode(cloud, expectedBookID: book.id) }
        #expect(throws: (any Error).self) { try SharedBookCloudCodec.decode(cloud, expectedBookID: privateBook.id) }
    }

    @Test func cloudCodecPreservesIdentityAndClearsAssetForDeletion() throws {
        let bookID = UUID()
        let id = SharedRecordID(bookID: bookID, kind: .transaction, entityID: UUID().uuidString)
        let value = SharedBookRecord(id: id, fields: ["amount": .decimal(123.45)])
        let zone = CKRecordZone.ID(zoneName: SharedBookCloudCodec.zoneName(bookID: bookID), ownerName: "participant-owner")
        let record = try SharedBookCloudCodec.encode(value, zoneID: zone)
        #expect(try SharedBookCloudCodec.decode(record, expectedBookID: bookID) == value)
        let deleted = try SharedBookCloudCodec.encode(value.tombstone(), zoneID: zone, existing: record)
        #expect(deleted === record)
        #expect(try SharedBookCloudCodec.decode(deleted, expectedBookID: bookID).deleted)
        #expect(deleted["file"] == nil)
        let otherZone = CKRecordZone.ID(zoneName: "Other", ownerName: "participant-owner")
        #expect(throws: (any Error).self) { try SharedBookCloudCodec.encode(value, zoneID: otherZone) }
        var foreignReference = value
        foreignReference.fields["conto"] = .reference(SharedRecordID(bookID: UUID(), kind: .conto, entityID: UUID().uuidString))
        #expect(throws: (any Error).self) { try SharedBookCloudCodec.encode(foreignReference, zoneID: zone) }
    }
}
