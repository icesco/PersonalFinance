import Foundation
import CoreData

/// Relocates a closed SwiftData SQLite store without dropping its journal or
/// external attachment storage. Called before any container opens the store.
enum LocalStoreMigration {
    enum MigrationError: Error { case destinationExists }

    static func copy(from source: URL, to destination: URL) throws {
        let files = FileManager.default
        guard !files.fileExists(atPath: destination.path) else {
            throw MigrationError.destinationExists
        }
        let parent = destination.deletingLastPathComponent()
        try files.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appendingPathComponent(".migration-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? files.removeItem(at: staging) }
        let stagedStore = staging.appendingPathComponent(destination.lastPathComponent)
        // This API copies the SQLite store as a unit, including external blobs.
        // It does not open a CloudKit container or require the source model.
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: NSManagedObjectModel())
        try coordinator.replacePersistentStore(
            at: stagedStore, withPersistentStoreFrom: source, type: .sqlite
        )
        let artifacts = try files.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)
            .sorted { lhs, rhs in
                if lhs == stagedStore { return false }
                if rhs == stagedStore { return true }
                return lhs.lastPathComponent < rhs.lastPathComponent
            }
        // Publish the main database last: its existence is the startup commit
        // marker. The source remains untouched for recovery after interruption.
        var published: [URL] = []
        do {
            for artifact in artifacts {
                let target = parent.appendingPathComponent(artifact.lastPathComponent)
                // A previous interrupted attempt may have published sidecars.
                if target != destination, files.fileExists(atPath: target.path) {
                    try files.removeItem(at: target)
                }
                try files.moveItem(at: artifact, to: target)
                published.append(target)
            }
        } catch {
            for target in published.reversed() { try? files.removeItem(at: target) }
            throw error
        }
    }
}
