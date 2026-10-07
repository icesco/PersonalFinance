import Foundation
import SwiftData
import Testing
@testable import FinanceCore

@MainActor
struct ContoLogoTests {
    @Test func logoSurvivesSaveSharingReplacementAndRemoval() throws {
        let source = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let book = Account(name: "Personale")
        let conto = Conto(name: "Banca", type: .checking)
        conto.logoData = Data([1, 2, 3])
        conto.account = book
        book.conti = [conto]
        source.mainContext.insert(book)
        try source.mainContext.save()
        let saved = try #require(ModelContext(source).fetch(FetchDescriptor<Conto>()).first)
        #expect(saved.logoData == Data([1, 2, 3]))
        let target = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let scope = SharedBookScope(ownerName: "owner", bookID: book.id)
        for bytes: Data? in [Data([1, 2, 3]), Data([4, 5]), nil] {
            conto.logoData = bytes
            try source.mainContext.save()
            let snapshot = try SharedBookExporter.export(bookID: book.id, container: source)
            _ = try SharedBookImporter.apply(scope: scope, records: snapshot.records, assets: snapshot.assets, container: target)
            let imported = try #require(ModelContext(target).fetch(FetchDescriptor<Conto>()).first)
            #expect(imported.logoData == bytes)
        }
    }

    @Test func oldSharedAccountsWithoutLogoStillImport() throws {
        let source = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let book = Account(name: "Casa")
        let conto = Conto(name: "Carta", type: .credit)
        conto.account = book; book.conti = [conto]
        source.mainContext.insert(book)
        try source.mainContext.save()
        let snapshot = try SharedBookExporter.export(bookID: book.id, container: source)
        #expect(snapshot.records.first { $0.id.kind == .conto }?.fields["logo"] == nil)
        let target = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        _ = try SharedBookImporter.apply(scope: SharedBookScope(ownerName: "owner", bookID: book.id), records: snapshot.records, assets: snapshot.assets, container: target)
        #expect(try ModelContext(target).fetch(FetchDescriptor<Conto>()).first?.logoData == nil)
    }

    @Test func malformedSharedLogoRollsBackImport() throws {
        let source = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let book = Account(name: "Casa")
        let conto = Conto(name: "Banca", type: .checking)
        conto.account = book; book.conti = [conto]
        source.mainContext.insert(book)
        try source.mainContext.save()
        let snapshot = try SharedBookExporter.export(bookID: book.id, container: source)
        let index = try #require(snapshot.records.firstIndex { $0.id.kind == .conto })
        for encoded in ["invalid!", Data(repeating: 1, count: 129 * 1024).base64EncodedString()] {
            var records = snapshot.records
            records[index].fields["logo"] = .text(encoded)
            let target = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
            #expect(throws: (any Error).self) {
                try SharedBookImporter.apply(scope: SharedBookScope(ownerName: "owner", bookID: book.id), records: records, assets: snapshot.assets, container: target)
            }
            #expect(try ModelContext(target).fetchCount(FetchDescriptor<Conto>()) == 0)
        }
    }

}
