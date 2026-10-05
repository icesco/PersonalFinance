import Foundation

/// Device-local acknowledged server payloads, never synced through SwiftData.
/// Atomic replacement preserves the previous checkpoint after a failed write.
@MainActor
public final class SharedBookShadowStore {
    public enum Failure: Error { case corruptCheckpoint }
    private struct Checkpoint: Codable {
        var version = 1
        let scope: SharedBookScope
        let records: [SharedBookRecord]
    }
    private let directory: URL
    public init(directory: URL) { self.directory = directory }

    public func read(scope: SharedBookScope) throws -> [SharedBookRecord]? {
        let url = file(scope)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let checkpoint = try JSONDecoder().decode(Checkpoint.self, from: Data(contentsOf: url))
        guard checkpoint.version == 1, checkpoint.scope == scope else { throw Failure.corruptCheckpoint }
        try validate(checkpoint.records, scope: scope)
        return checkpoint.records
    }
    public func write(scope: SharedBookScope, acknowledged records: [SharedBookRecord]) throws {
        try validate(records, scope: scope)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var excluded = URLResourceValues(); excluded.isExcludedFromBackup = true
        var directoryURL = directory
        try directoryURL.setResourceValues(excluded)
        let data = try JSONEncoder().encode(Checkpoint(scope: scope, records: records))
        #if os(iOS)
        try data.write(to: file(scope), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: file(scope), options: [.atomic])
        #endif
    }
    private func file(_ scope: SharedBookScope) -> URL { directory.appendingPathComponent(scope.key + ".json") }
    private func validate(_ records: [SharedBookRecord], scope: SharedBookScope) throws {
        guard Set(records.map(\.id)).count == records.count,
              records.allSatisfy({ $0.version == 1 && $0.id.bookID == scope.bookID && (!$0.deleted || $0.fields.isEmpty) }) else { throw Failure.corruptCheckpoint }
    }
}
