import Foundation
import SwiftData
import Testing
import FinanceCore
@testable import Personal_Finance

@MainActor struct CaptureDocumentReaderTests {
    @Test(arguments: ["text", "empty", "unreadable", "failure"])
    func completedReadingIsReusedByFreshContexts(outcome: String) async throws {
        let store = try CaptureStore.container(inMemory: true)
        let capture = PendingCapture(source: "share", sourceName: "Test", text: "", document: Data([1]))
        try CaptureStore.enqueue(capture, in: store)
        var reads = 0
        let result = try await CaptureDocumentReader.read(capture, in: store) { _, _ in
            reads += 1
            switch outcome {
            case "empty": return "  "
            case "unreadable": throw ReceiptReader.Failure.unreadable
            case "failure": throw CocoaError(.fileReadUnknown)
            default: return "TOTALE EUR 18,50"
            }
        }
        let fresh = try #require(CaptureStore.pending(in: store).first)
        let reused = try await CaptureDocumentReader.read(fresh, in: store) { _, _ in
            reads += 1
            return "Unexpected rereading"
        }
        #expect(reads == 1)
        #expect(reused.status == result.status)
        #expect(reused.text == result.text)
        #expect(fresh.documentReadStatus == result.status.rawValue)
        #expect(fresh.document == Data([1]))
        // A Share Extension retry must not replace the saved OCR result.
        try CaptureStore.enqueue(PendingCapture(id: capture.id, source: "share", sourceName: "Test", text: "", document: Data([1])), in: store)
        #expect(try CaptureStore.pending(in: store).first?.documentReadStatus == result.status.rawValue)
    }

    @Test func simultaneousListAndDetailShareOneReading() async throws {
        let store = try CaptureStore.container(inMemory: true)
        let capture = PendingCapture(source: "share", sourceName: "Test", text: "", document: Data([1]))
        try CaptureStore.enqueue(capture, in: store)
        var reads = 0
        let first = Task { @MainActor in
            try await CaptureDocumentReader.read(capture, in: store) { _, _ in
                reads += 1
                await Task.yield()
                return "EUR 20"
            }
        }
        let second = Task { @MainActor in
            try await CaptureDocumentReader.read(capture, in: store) { _, _ in
                reads += 1
                return "Unexpected second reading"
            }
        }
        let values = try await (first.value, second.value)
        #expect(reads == 1)
        #expect(values.0.text == values.1.text)
    }
    @Test func discardingDuringReadingDoesNotRecreateProposal() async throws {
        let store = try CaptureStore.container(inMemory: true)
        let capture = PendingCapture(source: "share", sourceName: "Test", text: "", document: Data([1]))
        try CaptureStore.enqueue(capture, in: store)
        let id = capture.id
        _ = try await CaptureDocumentReader.read(capture, in: store) { _, _ in
            try CaptureStore.discard(id: id, in: store)
            return "EUR 20"
        }
        #expect(try CaptureStore.pendingCount(in: store) == 0)
    }
}
