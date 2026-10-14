import Foundation
import UserNotifications

@MainActor
public protocol CaptureNotificationCenter: AnyObject {
    func isAuthorized() async -> Bool
    func requestAuthorization() async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func removeImportNotifications() async
}

@MainActor
private final class SystemCaptureNotificationCenter: CaptureNotificationCenter {
    private let center = UNUserNotificationCenter.current()

    func isAuthorized() async -> Bool {
        let status = await center.notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert])
    }

    func add(_ request: UNNotificationRequest) async throws { try await center.add(request) }

    func removeImportNotifications() async {
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.filter {
            CaptureImportNotifications.captureID(from: $0.identifier) != nil
        }.map(\.identifier))
        let delivered = await center.deliveredNotifications()
        center.removeDeliveredNotifications(withIdentifiers: delivered.filter {
            CaptureImportNotifications.captureID(from: $0.request.identifier) != nil
        }.map { $0.request.identifier })
    }
}

@MainActor
public final class CaptureImportNotifications {
    public static let shared = CaptureImportNotifications()
    public static let enabledKey = "capture.importNotifications.enabled"
    private static let prefix = "formi.capture."
    private let defaults: UserDefaults
    private let center: any CaptureNotificationCenter

    public init(defaults: UserDefaults? = nil, center: (any CaptureNotificationCenter)? = nil) {
        self.defaults = defaults ?? UserDefaults(suiteName: FinanceCoreModule.defaultAppGroupIdentifier) ?? .standard
        self.center = center ?? SystemCaptureNotificationCenter()
    }

    public var enabled: Bool { defaults.object(forKey: Self.enabledKey) as? Bool ?? true }
    public func isAuthorized() async -> Bool { await center.isAuthorized() }

    @discardableResult
    public func setEnabled(_ value: Bool) async throws -> Bool {
        if value, !(await center.isAuthorized()) {
            guard try await center.requestAuthorization() else { return false }
        }
        defaults.set(value, forKey: Self.enabledKey)
        if !value { await center.removeImportNotifications() }
        return true
    }

    public static func captureID(from identifier: String) -> UUID? {
        guard identifier.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(identifier.dropFirst(prefix.count)))
    }

    public static func request(for id: UUID) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Nuova proposta da approvare", bundle: Bundle(for: CaptureImportNotifications.self))
        content.body = String(localized: "Apri Formi per controllarla. Nessun movimento è stato registrato.", bundle: Bundle(for: CaptureImportNotifications.self))
        content.threadIdentifier = "formi.capture.imports"
        content.interruptionLevel = .passive
        return UNNotificationRequest(identifier: prefix + id.uuidString, content: content, trigger: nil)
    }

    /// Permission is requested only from settings. An unavailable alert must not fail an import.
    public func notify(captureID: UUID, isNew: Bool) async {
        guard isNew, enabled, await center.isAuthorized(), enabled else { return }
        try? await center.add(Self.request(for: captureID))
    }
}
