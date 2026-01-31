import Foundation
import SwiftData
import CloudKit

public struct FinanceCoreModule {
    public static let allModels: [any PersistentModel.Type] = [
        Account.self,
        AccountStatistics.self,
        Conto.self,
        Transaction.self,
        TransferLink.self,
        Category.self,
        Budget.self,
        BudgetCategory.self,
        SavingsGoal.self
    ]
    
    // MARK: - Configuration Constants
    
    public static let cloudKitContainerIdentifier = "iCloud.cc.francescobianco.personalfinance"
    public static let defaultAppGroupIdentifier = "group.personalfinance.shared"
    
    // MARK: - Shared Container Management

    @MainActor
    private static var _sharedContainer: ModelContainer?
    
    public static func createSchema() -> Schema {
        return Schema(allModels)
    }
    
    // MARK: - Dynamic Container Creation
    
    public static func createModelContainer(
        appGroupIdentifier: String = defaultAppGroupIdentifier,
        enableCloudKit: Bool = false,
        inMemory: Bool = false
    ) throws -> ModelContainer {
        let schema = createSchema()
        let configuration = createModelConfiguration(
            appGroupIdentifier: appGroupIdentifier,
            enableCloudKit: enableCloudKit,
            inMemory: inMemory
        )
        
        return try ModelContainer(for: schema, configurations: [configuration])
    }
    
    public static func createModelConfiguration(
        appGroupIdentifier: String = defaultAppGroupIdentifier,
        enableCloudKit: Bool = false,
        inMemory: Bool = false
    ) -> ModelConfiguration {
        let schema = createSchema()
        
        if inMemory {
            return ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        }
        
        // Determine storage URL based on App Group
        let url = containerURL(for: appGroupIdentifier)
        
        if enableCloudKit {
            return ModelConfiguration(
                schema: schema,
                url: url,
                cloudKitDatabase: .private(cloudKitContainerIdentifier)
            )
        } else {
            return ModelConfiguration(
                schema: schema,
                url: url
            )
        }
    }
    
    // MARK: - App Group Support
    
    private static func containerURL(for appGroupIdentifier: String) -> URL {
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            return containerURL.appendingPathComponent("PersonalFinance.sqlite")
        } else {
            // Fallback to app's documents directory
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            return documentsPath.appendingPathComponent("PersonalFinance.sqlite")
        }
    }
    
    // MARK: - Shared Container Management

    @MainActor
    public static func setSharedContainer(
        appGroupIdentifier: String = defaultAppGroupIdentifier,
        enableCloudKit: Bool = false
    ) throws {
        _sharedContainer = try createModelContainer(
            appGroupIdentifier: appGroupIdentifier,
            enableCloudKit: enableCloudKit
        )
    }

    @MainActor
    public static var sharedContainer: ModelContainer? {
        return _sharedContainer
    }
    
    // MARK: - Widget Support
    
    public static func widgetModelContainer(
        appGroupIdentifier: String = defaultAppGroupIdentifier
    ) throws -> ModelContainer {
        // Always use local storage for widgets, no CloudKit
        return try createModelContainer(
            appGroupIdentifier: appGroupIdentifier,
            enableCloudKit: false
        )
    }
    
    // MARK: - Legacy Support
    
    @available(*, deprecated, message: "Use createModelContainer(appGroupIdentifier:enableCloudKit:inMemory:) instead")
    public static func createModelContainer(inMemory: Bool = false) throws -> ModelContainer {
        return try createModelContainer(
            appGroupIdentifier: defaultAppGroupIdentifier,
            enableCloudKit: false,
            inMemory: inMemory
        )
    }
    
    @available(*, deprecated, message: "Use createModelConfiguration(appGroupIdentifier:enableCloudKit:inMemory:) instead")
    public static func createModelConfiguration(inMemory: Bool = false) -> ModelConfiguration {
        return createModelConfiguration(
            appGroupIdentifier: defaultAppGroupIdentifier,
            enableCloudKit: false,
            inMemory: inMemory
        )
    }
}

// MARK: - Data Storage Management

@Observable
@MainActor
public final class DataStorageManager {
    public static let shared = DataStorageManager()
    
    private let appGroupIdentifier: String
    private let userDefaults: UserDefaults
    
    // MARK: - Cloud Sync Preferences
    
    public var isCloudSyncEnabled: Bool {
        get {
            userDefaults.bool(forKey: "CloudSyncEnabled")
        }
        set {
            userDefaults.set(newValue, forKey: "CloudSyncEnabled")
            Task { @MainActor in
                await updateContainer()
            }
        }
    }
    
    public var currentContainer: ModelContainer? {
        return FinanceCoreModule.sharedContainer
    }
    
    // MARK: - Initialization
    
    public init(appGroupIdentifier: String = FinanceCoreModule.defaultAppGroupIdentifier) {
        self.appGroupIdentifier = appGroupIdentifier
        
        // Use App Group UserDefaults for shared preferences
        if let groupDefaults = UserDefaults(suiteName: appGroupIdentifier) {
            self.userDefaults = groupDefaults
        } else {
            self.userDefaults = UserDefaults.standard
        }
    }
    
    // MARK: - Container Management
    
    @MainActor
    public func initializeContainer() async throws {
        try FinanceCoreModule.setSharedContainer(
            appGroupIdentifier: appGroupIdentifier,
            enableCloudKit: isCloudSyncEnabled
        )
    }
    
    @MainActor
    private func updateContainer() async {
        do {
            try FinanceCoreModule.setSharedContainer(
                appGroupIdentifier: appGroupIdentifier,
                enableCloudKit: isCloudSyncEnabled
            )
        } catch {
            print("Failed to update container: \(error)")
        }
    }
    
    // MARK: - Migration Support
    
    public func needsMigration() -> Bool {
        // Check if old local database exists and needs migration to App Group
        let oldURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("PersonalFinance.sqlite")
        
        let newURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent("PersonalFinance.sqlite")
        
        return FileManager.default.fileExists(atPath: oldURL.path) && 
               (newURL == nil || !FileManager.default.fileExists(atPath: newURL!.path))
    }
    
    public func performMigration() throws {
        guard needsMigration() else { return }
        
        let oldURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("PersonalFinance.sqlite")
        
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            throw NSError(domain: "DataStorageManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not access App Group container"])
        }
        
        let newURL = containerURL.appendingPathComponent("PersonalFinance.sqlite")
        
        // Ensure destination directory exists
        try FileManager.default.createDirectory(
            at: containerURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        
        // Copy database files
        let fileManager = FileManager.default
        let extensions = ["", "-wal", "-shm"]
        
        for ext in extensions {
            let sourceURL = oldURL.appendingPathExtension(ext)
            let destURL = newURL.appendingPathExtension(ext)
            
            if fileManager.fileExists(atPath: sourceURL.path) {
                if fileManager.fileExists(atPath: destURL.path) {
                    try fileManager.removeItem(at: destURL)
                }
                try fileManager.copyItem(at: sourceURL, to: destURL)
            }
        }
    }
    
    // MARK: - CloudKit Status
    
    public func cloudKitAccountStatus() async -> CKAccountStatus {
        let container = CKContainer(identifier: FinanceCoreModule.cloudKitContainerIdentifier)
        return await withCheckedContinuation { continuation in
            container.accountStatus { status, _ in
                continuation.resume(returning: status)
            }
        }
    }
    
    public func isCloudKitAvailable() async -> Bool {
        let status = await cloudKitAccountStatus()
        return status == .available
    }
}

// MARK: - Utility Extensions

extension Decimal {
    public var currencyFormatted: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "EUR"
        return formatter.string(from: self as NSDecimalNumber) ?? "€0,00"
    }
}

extension Date {
    public var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }
    
    public var isThisWeek: Bool {
        Calendar.current.isDate(self, equalTo: Date(), toGranularity: .weekOfYear)
    }
    
    public var isThisMonth: Bool {
        Calendar.current.isDate(self, equalTo: Date(), toGranularity: .month)
    }
    
    public var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }
    
    public var startOfWeek: Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: self)
        return calendar.date(from: components) ?? self
    }
    
    public var startOfMonth: Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: self)
        return calendar.date(from: components) ?? self
    }
}
