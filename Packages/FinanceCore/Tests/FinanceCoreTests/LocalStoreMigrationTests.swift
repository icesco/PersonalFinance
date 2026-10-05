import Foundation
import SwiftData
import Testing
@testable import FinanceCore

@MainActor
struct LocalStoreMigrationTests {
    private func open(_ url: URL) throws -> ModelContainer {
        try ModelContainer(for: FinanceCoreModule.createSchema(), configurations: [
            ModelConfiguration(schema: FinanceCoreModule.createSchema(), url: url, cloudKitDatabase: .none)
        ])
    }

    @Test func preservesJournalTransactionsAndExternalAttachments() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("PersonalFinance.sqlite")
        let destination = directory.appendingPathComponent("group/PersonalFinance.sqlite")
        let original = try open(source)
        let bytes = Data((0..<2_000_000).map { UInt8($0 % 251) })
        let transaction = Transaction(amount: 42, type: .expense)
        transaction.attachments = [TransactionAttachment(filename: "receipt.pdf", contentType: "com.adobe.pdf", data: bytes)]
        original.mainContext.insert(transaction)
        try original.mainContext.save()
        let wal = URL(fileURLWithPath: source.path + "-wal")
        #expect(FileManager.default.fileExists(atPath: wal.path))
        // Keep the source open so the test really exercises uncheckpointed WAL.
        try LocalStoreMigration.copy(from: source, to: destination)
        let copiedArtifacts = try #require(FileManager.default.enumerator(
            at: destination.deletingLastPathComponent(), includingPropertiesForKeys: nil
        ))
        let externalPayloadWasCopied = copiedArtifacts.compactMap { $0 as? URL }.contains { url in
            url.path.contains("_SUPPORT") && (try? Data(contentsOf: url)) == bytes
        }
        #expect(externalPayloadWasCopied)
        let copied = try open(destination)
        let fetched = try #require(copied.mainContext.fetch(FetchDescriptor<Transaction>()).first)
        #expect(fetched.id == transaction.id)
        #expect(fetched.amount == 42)
        #expect(fetched.attachments?.first?.data == bytes)
        #expect(try original.mainContext.fetchCount(FetchDescriptor<Transaction>()) == 1)
        #expect(throws: LocalStoreMigration.MigrationError.self) {
            try LocalStoreMigration.copy(from: source, to: destination)
        }
        #expect(try copied.mainContext.fetchCount(FetchDescriptor<Transaction>()) == 1)
    }

    @Test func missingSourceDoesNotPublishEmptyDestination() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("missing.sqlite")
        let destination = directory.appendingPathComponent("group/PersonalFinance.sqlite")
        #expect(throws: (any Error).self) { try LocalStoreMigration.copy(from: source, to: destination) }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }
}
