import Foundation
import Testing
@testable import Personal_Finance

struct CSVExportFileTests {
    @Test func savingToExistingDestinationReplacesCSVContents() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("movimenti.csv")
        try "Vecchio contenuto".write(to: destination, atomically: true, encoding: .utf8)
        let csv = "Descrizione,Importo\nCaffè,2.50\n"

        try CSVExportFileWriter.write(csv, to: destination)

        #expect(try String(contentsOf: destination, encoding: .utf8) == csv)
    }

    @Test func invalidDestinationThrowsInsteadOfReportingSuccess() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(throws: (any Error).self) {
            try CSVExportFileWriter.write("Descrizione,Importo\n", to: directory)
        }
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
    }
}
