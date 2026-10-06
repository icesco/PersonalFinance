import CloudKit
import SwiftData
import Testing
import FinanceCore

/// Explicit opt-in only: uploads synthetic data to the signed-in iCloud account.
/// Never reads DataStorageManager or the user's persistent finance store.
@MainActor
struct LiveCloudVerificationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.arguments.contains("FORGIA_VERIFY_LIVE_CLOUD")
                  && ProcessInfo.processInfo.arguments.contains("UITEST_MAC_LOCAL")))
    func syntheticOwnerBookRoundTrip() async throws {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let book = Account(name: "Forgia verifica sintetica", currency: "EUR")
        let conto = Conto(name: "Conto sintetico", type: .checking, initialBalance: 100)
        conto.account = book
        book.conti = [conto]
        let expense = FinanceCore.Transaction(amount: Decimal(string: "12.50")!, type: .expense)
        expense.setFromConto(conto)
        let bytes = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII="))
        let attachment = TransactionAttachment(filename: "prova.png", contentType: "public.png", data: bytes)
        expense.attachments = [attachment]
        container.mainContext.insert(book)
        container.mainContext.insert(expense)
        try container.mainContext.save()

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ForgiaCloudVerification-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = SharedBookCloudTransport(configuration: { (true, 1) })
        let coordinator = SharedBookSyncCoordinator(transport: transport, shadows: SharedBookShadowStore(directory: directory),
                                                  configuration: { (container, 1, true) })
        let database = CKContainer(identifier: FinanceCoreModule.cloudKitContainerIdentifier).privateCloudDatabase
        let zoneID = CKRecordZone.ID(zoneName: SharedBookCloudCodec.zoneName(bookID: book.id), ownerName: CKCurrentUserDefaultName)
        // UUID generated in this invocation: cleanup can never target a user's book.
        do {
            guard case let .ready(scope, share) = try await coordinator.prepareOwnerShare(bookID: book.id) else {
                Issue.record("Unexpected conflict in a new synthetic book")
                try await removeTestZone(database, zoneID)
                return
            }
            #expect(share.publicPermission == .none)
            let first = try await transport.fetch(scope: scope, role: .owner)
            let expected = try SharedBookExporter.export(bookID: book.id, container: container)
            #expect(Set(first.records.map(\.id)) == Set(expected.records.map(\.id)))
            #expect(first.assets == expected.assets)
            for record in expected.records {
                #expect(first.records.first { $0.id == record.id } == record)
            }

            // Use a fresh context: synchronization can save through another context.
            let context = ModelContext(container)
            let savedExpense = try #require(context.fetch(FetchDescriptor<FinanceCore.Transaction>()).first)
            savedExpense.amount = 18
            let savedAttachment = try #require(savedExpense.attachments?.first)
            savedAttachment.filename = "prova-aggiornata.png"
            try context.save()
            guard case .synchronized = try await coordinator.synchronize(scope: scope, role: .owner) else {
                Issue.record("Unexpected conflict while updating the synthetic book")
                try await removeTestZone(database, zoneID)
                return
            }
            let second = try await transport.fetch(scope: scope, role: .owner)
            #expect(second.records.first { $0.id.kind == .transaction }?.fields["amount"] == .decimal(18))
            #expect(second.records.first { $0.id.kind == .attachment }?.fields["filename"] == .text("prova-aggiornata.png"))
            #expect(second.assets == expected.assets)
            try await removeTestZone(database, zoneID)
        } catch {
            do { try await removeTestZone(database, zoneID) }
            catch { Issue.record("Synthetic zone cleanup failed: \(zoneID.zoneName): \(error)") }
            throw error
        }
    }

    private func removeTestZone(_ database: CKDatabase, _ id: CKRecordZone.ID) async throws {
        do { _ = try await database.deleteRecordZone(withID: id) }
        catch let error as CKError where error.code == .zoneNotFound || error.code == .unknownItem { }
    }
}
