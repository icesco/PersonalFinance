import Foundation

/// Aggregates overlapping mirroring events into one observable sync cycle.
public struct CloudSyncProgress {
    private var activeEvents: Set<UUID> = []
    private var completedDataDate: Date?
    public private(set) var error: (any Error)?
    public private(set) var lastSyncDate: Date?
    public var isSyncing: Bool { !activeEvents.isEmpty }

    public init() {}

    /// Returns true only when a new cycle starts.
    @discardableResult
    public mutating func begin(_ id: UUID) -> Bool {
        let startsCycle = activeEvents.isEmpty
        if startsCycle {
            error = nil
            completedDataDate = nil
        }
        activeEvents.insert(id)
        return startsCycle
    }

    /// Unknown or duplicate completions cannot finish the current cycle.
    /// Setup success alone does not prove that any data was synchronized.
    @discardableResult
    public mutating func finish(_ id: UUID, at date: Date, isDataSync: Bool,
                                error eventError: (any Error)?) -> Bool {
        guard activeEvents.remove(id) != nil else { return false }
        if let eventError { error = eventError }
        if eventError == nil, isDataSync {
            completedDataDate = max(completedDataDate ?? date, date)
        }
        guard activeEvents.isEmpty else { return false }
        if error == nil, let completedDataDate {
            lastSyncDate = max(lastSyncDate ?? completedDataDate, completedDataDate)
        }
        return true
    }
}
