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
    var isSyncing: Bool { progress.isSyncing }
    var lastSyncDate: Date? { progress.lastSyncDate }
    var syncError: Error? { progress.error }
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
            let failure: Error? = event.error ?? (event.succeeded ? nil : CloudEventFailure())
            let completedCycle = progress.finish(
                event.identifier, at: endDate,
                isDataSync: event.type != .setup, error: failure
            )
            guard completedCycle else { return }
            if let error = progress.error {
                NotificationCenter.default.post(
                    name: .cloudSyncDidFail, object: nil, userInfo: ["error": error]
                )
            } else {
                NotificationCenter.default.post(name: .cloudSyncDidComplete, object: nil)
            }
        } else if progress.begin(event.identifier) {
            NotificationCenter.default.post(name: .cloudSyncDidBegin, object: nil)
        }
    }

    private struct CloudEventFailure: LocalizedError {
        var errorDescription: String? { "Sincronizzazione iCloud non riuscita. Riprova più tardi." }
    }

    private func resetStatus() {
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
