import Foundation

public enum CloudSyncSessionStep: Equatable, Sendable {
    case none, announce, completed, failed, stale
}

/// Groups short mirroring waves across gaps without claiming that silence proves success.
/// No timers or platform state: callers advance it using their own clock.
public struct CloudSyncSession: Sendable {
    public let announcementDelay: TimeInterval
    public let quiescenceDelay: TimeInterval
    public let stalenessDelay: TimeInterval
    private var startedAt: Date?
    private var lastActivity: Date?
    private var hasActiveEvents = false
    private var hasFailure = false
    private var announced = false
    public var isActive: Bool { startedAt != nil }

    public init(announcementDelay: TimeInterval = 3, quiescenceDelay: TimeInterval = 2,
                stalenessDelay: TimeInterval = 20) {
        self.announcementDelay = announcementDelay
        self.quiescenceDelay = quiescenceDelay
        self.stalenessDelay = stalenessDelay
    }

    /// A tracked failure after timeout is delivered immediately, without reopening progress.
    @discardableResult
    public mutating func activity(at now: Date, hasActiveEvents: Bool, failed: Bool = false) -> CloudSyncSessionStep {
        if startedAt == nil {
            if failed { return .failed }
            guard hasActiveEvents else { return .none } // A late success never reopens a closed session.
            startedAt = now
            hasFailure = false
            announced = false
        }
        lastActivity = now
        self.hasActiveEvents = hasActiveEvents
        hasFailure = hasFailure || failed
        return .none
    }

    public var nextDeadline: Date? {
        guard let start = startedAt, let last = lastActivity else { return nil }
        let end = last.addingTimeInterval(hasActiveEvents ? stalenessDelay : quiescenceDelay)
        return announced ? end : min(end, start.addingTimeInterval(announcementDelay))
    }

    public mutating func advance(to now: Date) -> CloudSyncSessionStep {
        guard let start = startedAt, let last = lastActivity else { return .none }
        let end = last.addingTimeInterval(hasActiveEvents ? stalenessDelay : quiescenceDelay)
        if now >= end {
            let step: CloudSyncSessionStep = hasFailure ? .failed : hasActiveEvents ? .stale : .completed
            startedAt = nil; lastActivity = nil; hasFailure = false; announced = false; hasActiveEvents = false
            return step
        }
        if !announced && now >= start.addingTimeInterval(announcementDelay) {
            announced = true
            return .announce
        }
        return .none
    }
}
