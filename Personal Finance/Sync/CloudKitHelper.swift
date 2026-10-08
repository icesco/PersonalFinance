//
//  CloudKitHelper.swift
//  Personal Finance
//
//  Observable singleton that tracks CloudKit sync state by listening
//  to NSPersistentCloudKitContainer event notifications.
//

import Foundation
import CloudKit
import CoreData
import Observation
import FinanceCore

@Observable
@MainActor
final class CloudKitHelper {
    static let shared = CloudKitHelper()

    // MARK: - Published State

    private var progress = CloudSyncProgress()
    private var session = CloudSyncSession()
    @ObservationIgnored private var sessionTask: Task<Void, Never>?
    private var sessionError: Error?
    var isSyncing: Bool { session.isActive }
    var lastSyncDate: Date? { progress.lastSyncDate }
    var syncError: Error? { sessionError ?? progress.error }
    private(set) var isCloudKitAvailable = false
    private(set) var isAccountConnected = false

    // MARK: - Computed

    var syncStatusMessage: String {
        if !DataStorageManager.shared.isCloudSyncEnabled {
            return "Sincronizzazione disattivata"
        }
        if !isCloudKitAvailable {
            return "iCloud non disponibile"
        }
        if !isAccountConnected {
            return "Account iCloud non connesso"
        }
        if isSyncing {
            return "Sincronizzazione in corso..."
        }
        if let error = syncError {
            return "Errore: \(error.localizedDescription)"
        }
        if let date = lastSyncDate {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            return "Aggiornato \(formatter.localizedString(for: date, relativeTo: Date()))"
        }
        return "In attesa di sincronizzazione"
    }

    // MARK: - Init

    private init() {
        NotificationCenter.default.addObserver(forName: .containerDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.resetStatus() }
        }
        // SwiftData forwards the public Core Data mirroring events.
        let eventNotification = NSPersistentCloudKitContainer.eventChangedNotification
        NotificationCenter.default.addObserver(
            forName: eventNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.handleCloudKitEvent(notification)
            }
        }
    }

    // MARK: - Event Handling

    private func handleCloudKitEvent(_ notification: Notification) {
        guard DataStorageManager.shared.isCloudSyncEnabled else {
            resetStatus()
            return
        }
        guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
            as? NSPersistentCloudKitContainer.Event else { return }

        if let endDate = event.endDate {
            guard progress.isTracking(event.identifier) else { return }
            let failure: Error? = event.error ?? (event.succeeded ? nil : CloudEventFailure())
            progress.finish(event.identifier, at: endDate, isDataSync: event.type != .setup, error: failure)
            if let failure { sessionError = failure }
            publish(session.activity(at: Date(), hasActiveEvents: progress.isSyncing, failed: failure != nil))
        } else {
            guard !progress.isTracking(event.identifier) else { return }
            if !session.isActive { sessionError = nil }
            progress.begin(event.identifier)
            session.activity(at: Date(), hasActiveEvents: true)
        }
        scheduleSessionAdvance()
    }

    private func scheduleSessionAdvance() {
        sessionTask?.cancel()
        guard let deadline = session.nextDeadline else { sessionTask = nil; return }
        sessionTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow))) }
            catch { return }
            guard let self, !Task.isCancelled else { return }
            publish(session.advance(to: Date()))
            scheduleSessionAdvance()
        }
    }

    private func publish(_ step: CloudSyncSessionStep) {
        switch step {
        case .announce:
            NotificationCenter.default.post(name: .cloudSyncDidBegin, object: nil)
        case .completed:
            NotificationCenter.default.post(name: .cloudSyncDidComplete, object: nil)
        case .failed:
            NotificationCenter.default.post(name: .cloudSyncDidFail, object: nil,
                                            userInfo: sessionError.map { ["error": $0] })
        case .stale:
            // Missing end events do not prove a successful import/export.
            NotificationCenter.default.post(name: .cloudSyncSessionDidEnd, object: nil)
        case .none: break
        }
    }

    private struct CloudEventFailure: LocalizedError {
        var errorDescription: String? { "Sincronizzazione iCloud non riuscita. Riprova più tardi." }
    }

    private func resetStatus() {
        sessionTask?.cancel()
        sessionTask = nil
        session = CloudSyncSession()
        sessionError = nil
        progress = CloudSyncProgress()
        isCloudKitAvailable = false
        isAccountConnected = false
    }

    // MARK: - Account Status

    func refreshSyncStatus() async {
        guard DataStorageManager.shared.isCloudSyncEnabled else {
            resetStatus()
            return
        }
        let generation = DataStorageManager.shared.containerGeneration
        let status = await DataStorageManager.shared.cloudKitAccountStatus()
        guard DataStorageManager.shared.isCloudSyncEnabled else {
            resetStatus()
            return
        }
        guard generation == DataStorageManager.shared.containerGeneration else { return }
        isCloudKitAvailable = status != .noAccount && status != .couldNotDetermine
        isAccountConnected = status == .available
    }
}
