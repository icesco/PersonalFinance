import Foundation
import Testing
import UserNotifications
@testable import FinanceCore

@MainActor
struct CaptureImportNotificationTests {
    private final class Center: CaptureNotificationCenter {
        var authorized = true
        var permissionRequests = 0
        var removals = 0
        var fails = false
        var requests: [UNNotificationRequest] = []
        var onAuthorizationCheck: (() -> Void)?
        func isAuthorized() async -> Bool {
            onAuthorizationCheck?()
            return authorized
        }
        func requestAuthorization() async throws -> Bool { permissionRequests += 1; return authorized }
        func add(_ request: UNNotificationRequest) async throws {
            if fails { throw CocoaError(.fileWriteUnknown) }
            requests.append(request)
        }
        func removeImportNotifications() async { removals += 1; requests = [] }
    }

    @Test func notificationIsSilentPrivateGroupedAndRoutesOnlyValidIdentifiers() {
        let id = UUID()
        let request = CaptureImportNotifications.request(for: id)
        #expect(CaptureImportNotifications.captureID(from: request.identifier) == id)
        #expect(CaptureImportNotifications.captureID(from: "formi.capture.invalid") == nil)
        #expect(CaptureImportNotifications.captureID(from: "forgia.recurrence.\(id)") == nil)
        #expect(request.content.title == "Nuova proposta da approvare")
        #expect(request.content.body == "Apri Formi per controllarla. Nessun movimento è stato registrato.")
        #expect(request.content.sound == nil)
        #expect(request.content.badge == nil)
        #expect(request.content.userInfo.isEmpty)
        #expect(request.content.interruptionLevel == .passive)
        #expect(request.trigger == nil)
        let other = CaptureImportNotifications.request(for: UUID())
        #expect(request.identifier != other.identifier)
        #expect(request.content.threadIdentifier == other.content.threadIdentifier)
    }

    @Test func acquisitionRetryDoesNotNotifyTwiceOrRequestPermission() async throws {
        let name = "capture-notifications-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let center = Center()
        let service = CaptureImportNotifications(defaults: defaults, center: center)
        let store = try CaptureStore.container(inMemory: true)
        let id = UUID()
        for _ in 0..<2 {
            let capture = PendingCapture(id: id, source: "notification", sourceName: "Banca privata", text: "EUR 25")
            let isNew = try CaptureStore.enqueue(capture, in: store)
            await service.notify(captureID: id, isNew: isNew)
        }
        #expect(center.requests.count == 1)
        #expect(center.permissionRequests == 0)
        #expect(try CaptureStore.pendingCount(in: store) == 1)
    }

    @Test func disabledDeniedOrFailedAlertsDoNotInterruptAnImport() async throws {
        let name = "capture-notifications-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let center = Center()
        let service = CaptureImportNotifications(defaults: defaults, center: center)
        await service.notify(captureID: UUID(), isNew: true)
        #expect(center.requests.count == 1)
        #expect(try await service.setEnabled(false))
        #expect(!service.enabled)
        #expect(center.removals == 1)
        await service.notify(captureID: UUID(), isNew: true)
        #expect(center.requests.isEmpty)
        center.authorized = false
        #expect(try await !service.setEnabled(true))
        #expect(!service.enabled)
        #expect(center.permissionRequests == 1)
        defaults.set(true, forKey: CaptureImportNotifications.enabledKey)
        await service.notify(captureID: UUID(), isNew: true)
        #expect(center.requests.isEmpty)
        #expect(center.permissionRequests == 1)
        center.authorized = true
        center.fails = true
        await service.notify(captureID: UUID(), isNew: true)
        #expect(center.requests.isEmpty)
    }

    @Test func disableDuringPermissionReadSuppressesTheAlert() async {
        let name = "capture-notifications-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let center = Center()
        let service = CaptureImportNotifications(defaults: defaults, center: center)
        center.onAuthorizationCheck = { defaults.set(false, forKey: CaptureImportNotifications.enabledKey) }
        await service.notify(captureID: UUID(), isNew: true)
        #expect(center.requests.isEmpty)
    }
}
