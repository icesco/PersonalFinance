#if DEBUG
import CoreData
import Foundation
import SwiftData

/// Pushes the complete schema of every SwiftData model to the CloudKit **Development** environment.
///
/// CloudKit only creates the fields it receives with a value, so syncing real data leaves the
/// schema incomplete. `initializeCloudKitSchema()` uploads one sample record per entity with every
/// field filled, then deletes it. Production is untouched: its schema changes only via a deploy.
public enum CloudKitSchemaInitializer {
    public enum Failure: Error, LocalizedError {
        case modelConversion

        public var errorDescription: String? {
            "Impossibile convertire i modelli SwiftData nel formato richiesto da CloudKit."
        }
    }

    public static let launchArgument = "INITIALIZE_CLOUDKIT_SCHEMA"

    public static func initialize(
        containerIdentifier: String = FinanceCoreModule.cloudKitContainerIdentifier
    ) throws {
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: FinanceCoreModule.allModels) else {
            throw Failure.modelConversion
        }
        // A throwaway store: the app's own data is never loaded by this container. It is left in
        // tmp for the system to purge, since CloudKit may still hold it open after this returns.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CloudKitSchema-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let description = NSPersistentStoreDescription(url: directory.appendingPathComponent("Schema.sqlite"))
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: containerIdentifier)
        description.shouldAddStoreAsynchronously = false

        let container = NSPersistentCloudKitContainer(name: "CloudKitSchema", managedObjectModel: model)
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }

        try container.initializeCloudKitSchema(options: [])
    }

    /// Runs off the main thread: the call blocks until CloudKit answers, and the mirroring
    /// delegate needs the main thread free to finish its setup.
    public static func initializeInBackground(
        containerIdentifier: String = FinanceCoreModule.cloudKitContainerIdentifier
    ) async throws {
        try await Task.detached(priority: .userInitiated) {
            try initialize(containerIdentifier: containerIdentifier)
        }.value
    }
}
#endif
