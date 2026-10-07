import Foundation
import SwiftData
import Darwin

@MainActor public enum CaptureStore {
    public enum Failure: LocalizedError {
        case unavailable, empty, tooLarge, reusedID
        public var errorDescription: String? {
            switch self {
            case .unavailable: "L’archivio delle proposte non è disponibile. Apri Formi e riprova."
            case .empty: "Condividi del testo, un PDF o un’immagine leggibile."
            case .reusedID: "Questo identificativo è già associato a un’altra proposta. Usa un identificativo diverso."
            case .tooLarge: "Il testo deve essere entro 30.000 caratteri e ogni documento entro 10 MB."
            }
        }
    }
    public static func container(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([PendingCapture.self])
        if inMemory {
            return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        }
        guard let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: FinanceCoreModule.defaultAppGroupIdentifier) else { throw Failure.unavailable }
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: root.appendingPathComponent("CaptureInbox.sqlite"), cloudKitDatabase: .none)])
    }

    /// Serialize writers across the app and Share Extension. Do not lock the ledger.
    public static func enqueue(_ capture: PendingCapture) throws {
        guard let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: FinanceCoreModule.defaultAppGroupIdentifier) else { throw Failure.unavailable }
        let descriptor = open(root.appendingPathComponent("capture-inbox.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw Failure.unavailable }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw Failure.unavailable }
        defer { flock(descriptor, LOCK_UN) }
        try enqueue(capture, in: container())
    }

    /// Inject an isolated store for tests; production writers use the locked entry point.
    public static func enqueue(_ capture: PendingCapture, in container: ModelContainer) throws {
        guard !capture.originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || capture.document?.isEmpty == false else { throw Failure.empty }
        guard capture.originalText.count <= 30_000, (capture.document?.count ?? 0) <= 10 * 1024 * 1024 else { throw Failure.tooLarge }
        let context = ModelContext(container)
        let id = capture.id
        if let existing = try context.fetch(FetchDescriptor<PendingCapture>(predicate: #Predicate { $0.id == id })).first {
            guard existing.originalText == capture.originalText, existing.destinationName == capture.destinationName,
                  existing.source == capture.source, existing.sourceName == capture.sourceName,
                  existing.filename == capture.filename, existing.contentType == capture.contentType, existing.document == capture.document else { throw Failure.reusedID }
            return
        }
        context.insert(capture)
        try context.save()
    }

    public static func pending(in container: ModelContainer) throws -> [PendingCapture] {
        try ModelContext(container).fetch(FetchDescriptor<PendingCapture>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
    }
    public static func pendingCount(in container: ModelContainer) throws -> Int {
        try ModelContext(container).fetchCount(FetchDescriptor<PendingCapture>())
    }
    /// Continue from the oldest loaded date. Exclude loaded IDs at that date so
    /// equal timestamps, deletions and newer arrivals cannot shift page offsets.
    public static func pendingPage(in container: ModelContainer, before date: Date? = nil,
                                   excludingBoundaryIDs ids: [UUID] = [], limit: Int = 30) throws -> [PendingCapture] {
        let predicate: Predicate<PendingCapture>?
        if let date {
            predicate = #Predicate { $0.createdAt <= date && !ids.contains($0.id) }
        } else { predicate = nil }
        var descriptor = FetchDescriptor<PendingCapture>(predicate: predicate, sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = max(1, limit)
        return try ModelContext(container).fetch(descriptor)
    }
    public static func discard(id: UUID, in container: ModelContainer) throws {
        let context = ModelContext(container)
        for item in try context.fetch(FetchDescriptor<PendingCapture>(predicate: #Predicate { $0.id == id })) { context.delete(item) }
        try context.save()
    }
    public static func eraseAll() throws {
        let context = ModelContext(try container())
        try context.delete(model: PendingCapture.self)
        try context.save()
    }
}
