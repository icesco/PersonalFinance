import FinanceCore
import SwiftData
import Foundation

/// One reading per proposal, shared by list and detail and retained across launches.
@MainActor enum CaptureDocumentReader {
    enum Status: String, Sendable { case recognized, empty, failed }
    struct Result: Sendable {
        let status: Status
        let text: String
    }
    private static var tasks: [UUID: Task<Result, Error>] = [:]

    static func read(_ capture: PendingCapture, in container: ModelContainer? = nil,
                     recognize: @escaping @MainActor (Data, Bool) async throws -> String = { data, isPDF in
                         try await ReceiptReader.read(data: data, isPDF: isPDF)
                     }) async throws -> Result {
        let id = capture.id
        if let task = tasks[id] { return try await task.value }
        // Use a fresh inbox context: rows may still hold an older fetched instance.
        let inbox = try container ?? CaptureStore.container()
        let context = ModelContext(inbox)
        guard let stored = try context.fetch(FetchDescriptor<PendingCapture>(predicate: #Predicate { $0.id == id })).first else {
            throw CaptureStore.Failure.unavailable
        }
        if let raw = stored.documentReadStatus, let status = Status(rawValue: raw) {
            return Result(status: status, text: stored.documentText ?? "")
        }
        guard let data = stored.document else { return Result(status: .empty, text: "") }
        // Owned by the reader, so leaving a row does not cancel its shared reading.
        let task = Task { @MainActor in
            let result: Result
            do {
                let text = try await recognize(data, stored.contentType == "com.adobe.pdf")
                result = Result(status: text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .empty : .recognized, text: text)
            } catch ReceiptReader.Failure.unreadable {
                result = Result(status: .empty, text: "")
            } catch {
                result = Result(status: .failed, text: "")
            }
            // It may have been discarded while OCR was running. Never save an
            // outdated model instance after another context has deleted it.
            let writer = ModelContext(inbox)
            if let current = try writer.fetch(FetchDescriptor<PendingCapture>(predicate: #Predicate { $0.id == id })).first {
                current.documentText = result.text
                current.documentReadStatus = result.status.rawValue
                try writer.save()
            }
            return result
        }
        tasks[id] = task
        defer { tasks[id] = nil }
        return try await task.value
    }
}
