import Foundation
import SwiftData
import CloudKit

public struct FinanceCoreModule {
    public static let allModels: [any PersistentModel.Type] = [
        Account.self,
        Conto.self,
        Transaction.self,
        TransactionAttachment.self,
        RecurrenceResolution.self,
        RemoteExpenseReceipt.self,
        SharedBookMembership.self,
        SharedBookDeparture.self,
        SharedBookRecordLink.self,
        Category.self,
        Budget.self,
        SavingsGoal.self
    ]
    
    // MARK: - Configuration Constants
    
    public static let cloudKitContainerIdentifier = "iCloud.cc.francescobianco.personalfinance"
    public static let defaultAppGroupIdentifier = "group.personalfinance.shared"
    
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
            return ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
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
                url: url,
                cloudKitDatabase: .none
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
    public static let shared: DataStorageManager = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("UITEST_MAC_LOCAL") {
            return makeLocalTestStorage()
        }
        #endif
        return DataStorageManager()
    }()

    #if DEBUG
    /// Local UI verification without opening the user's store or contacting CloudKit.
    public static func makeLocalTestStorage() -> DataStorageManager {
        DataStorageManager(
            appGroupIdentifier: "Forgia.UITest",
            userDefaults: UserDefaults(suiteName: "Forgia.UITest.\(UUID().uuidString)")!,
            makeContainer: { enabled in
                guard !enabled else {
                    throw NSError(domain: "Forgia.LocalUITest", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "iCloud non è disponibile nella sessione di prova."])
                }
                return try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
            },
            requestAccountStatus: { .noAccount }
        )
    }
    #endif
    
    private let appGroupIdentifier: String
    private let userDefaults: UserDefaults
    private let makeContainer: @MainActor (Bool) throws -> ModelContainer
    private let requestAccountStatus: @MainActor () async -> CKAccountStatus
    
    // MARK: - Cloud Sync Preferences

    public private(set) var isCloudSyncEnabled: Bool
    public private(set) var syncToggleError: String?

    /// True while the container is being recreated after a sync toggle.
    public var isMigrating: Bool = false

    public private(set) var currentContainer: ModelContainer?
    public private(set) var containerGeneration = 0

    @ObservationIgnored private var automaticRefresh: SharedBookAutomaticRefresh?
    public var sharedBookAutomaticRefresh: SharedBookAutomaticRefresh {
        if let automaticRefresh { return automaticRefresh }
        let service = SharedBookAutomaticRefresh(configuration: { [weak self] in
            guard let self else { return (nil, -1, false) }
            return (self.currentContainer, self.containerGeneration, self.isCloudSyncEnabled && !self.isMigrating)
        }, synchronize: { [weak self] scope, role in
            guard let self else { throw SharedBookSyncCoordinator.Failure.unavailable }
            return try await self.sharedBookCoordinator.synchronize(scope: scope, role: role)
        })
        automaticRefresh = service
        return service
    }

    @ObservationIgnored private var sharedTransport: SharedBookCloudTransport?
    @ObservationIgnored private var sharedCoordinator: SharedBookSyncCoordinator?
    public var sharedBookCoordinator: SharedBookSyncCoordinator {
        if let sharedCoordinator { return sharedCoordinator }
        let directory = URL.applicationSupportDirectory.appendingPathComponent("Forgia/SharedBookShadows", isDirectory: true)
        let coordinator = SharedBookSyncCoordinator(transport: sharedBookTransport, shadows: SharedBookShadowStore(directory: directory)) { [weak self] in
            guard let self else { return (nil, -1, false) }
            return (self.currentContainer, self.containerGeneration, self.isCloudSyncEnabled && !self.isMigrating)
        }
        sharedCoordinator = coordinator
        return coordinator
    }
    public var sharedBookTransport: SharedBookCloudTransport {
        if let sharedTransport { return sharedTransport }
        let transport = SharedBookCloudTransport { [weak self] in
            guard let self else { return (false, -1) }
            return (self.isCloudSyncEnabled && !self.isMigrating, self.containerGeneration)
        }
        sharedTransport = transport
        return transport
    }
    
    // MARK: - Initialization
    
    public convenience init(appGroupIdentifier: String = FinanceCoreModule.defaultAppGroupIdentifier) {
        self.init(
            appGroupIdentifier: appGroupIdentifier,
            userDefaults: UserDefaults(suiteName: appGroupIdentifier) ?? .standard,
            makeContainer: { enabled in
                try FinanceCoreModule.createModelContainer(
                    appGroupIdentifier: appGroupIdentifier, enableCloudKit: enabled
                )
            },
            requestAccountStatus: {
                let container = CKContainer(identifier: FinanceCoreModule.cloudKitContainerIdentifier)
                return await withCheckedContinuation { continuation in
                    container.accountStatus { status, _ in continuation.resume(returning: status) }
                }
            }
        )
    }

    // Inject services in tests without opening a real cloud store or contacting iCloud.
    init(
        appGroupIdentifier: String,
        userDefaults: UserDefaults,
        makeContainer: @escaping @MainActor (Bool) throws -> ModelContainer,
        requestAccountStatus: @escaping @MainActor () async -> CKAccountStatus
    ) {
        self.appGroupIdentifier = appGroupIdentifier
        self.userDefaults = userDefaults
        self.makeContainer = makeContainer
        self.requestAccountStatus = requestAccountStatus
        self.isCloudSyncEnabled = userDefaults.bool(forKey: "CloudSyncEnabled")
    }

    // MARK: - Container Management
    
    @MainActor
    public func initializeContainer() async throws {
        guard currentContainer == nil else { return }
        try replaceContainer(enableCloud: isCloudSyncEnabled)
    }

    /// The container being replaced. Views built on it are swapped out by `containerGeneration`,
    /// but they can render once more first: releasing it now would invalidate their models
    /// and SwiftData would trap on the next property read.
    @ObservationIgnored private var retiredContainer: ModelContainer?

    private func replaceContainer(enableCloud: Bool) throws {
        try currentContainer?.mainContext.save()
        let replacement = try makeContainer(enableCloud)
        retiredContainer = currentContainer
        currentContainer = replacement
        containerGeneration += 1
    }

    /// Commit the preference only after successfully opening the new configuration.
    public func performSyncToggle(enableCloud: Bool) async {
        guard !isMigrating, enableCloud != isCloudSyncEnabled else { return }
        isMigrating = true
        sharedTransport?.cancelPendingRequests()
        syncToggleError = nil
        defer { isMigrating = false }
        do {
            try replaceContainer(enableCloud: enableCloud)
            isCloudSyncEnabled = enableCloud
            userDefaults.set(enableCloud, forKey: "CloudSyncEnabled")
            NotificationCenter.default.post(name: Notification.Name("containerDidChange"), object: nil)
        } catch {
            syncToggleError = error.localizedDescription
        }
    }

    public func clearSyncToggleError() { syncToggleError = nil }

    // MARK: - Migration Support
    
    public func needsMigration() -> Bool {
        // Check if old local database exists and needs migration to App Group
        let oldURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("PersonalFinance.sqlite")
        
        guard let newURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent("PersonalFinance.sqlite") else {
            // Unsigned simulator builds use the local Documents fallback; there is
            // no migration destination until the App Group becomes available.
            return false
        }

        return FileManager.default.fileExists(atPath: oldURL.path) &&
               !FileManager.default.fileExists(atPath: newURL.path)
    }
    
    public func performMigration() throws {
        guard needsMigration() else { return }
        
        let oldURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("PersonalFinance.sqlite")
        
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            throw NSError(domain: "DataStorageManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not access App Group container"])
        }
        
        let newURL = containerURL.appendingPathComponent("PersonalFinance.sqlite")
        
        try LocalStoreMigration.copy(from: oldURL, to: newURL)
    }
    
    // MARK: - CloudKit Status
    
    public func cloudKitAccountStatus() async -> CKAccountStatus {
        guard isCloudSyncEnabled else { return .couldNotDetermine }
        let generation = containerGeneration
        let status = await requestAccountStatus()
        // A response belongs to the configuration that initiated it, even when
        // the user has switched off and back on while the request was in flight.
        guard isCloudSyncEnabled, containerGeneration == generation else { return .couldNotDetermine }
        return status
    }
    
    public func isCloudKitAvailable() async -> Bool {
        let status = await cloudKitAccountStatus()
        return status == .available
    }
}

// MARK: - Utility Extensions

extension Decimal {
    public var doubleValue: Double {
        NSDecimalNumber(decimal: self).doubleValue
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
