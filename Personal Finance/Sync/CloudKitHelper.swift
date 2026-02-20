//
//  CloudKitHelper.swift
//  Personal Finance
//
//  Observable singleton that tracks CloudKit sync state by listening
//  to NSPersistentCloudKitContainer event notifications.
//

import Foundation
import CloudKit
import Observation
import FinanceCore

@Observable
@MainActor
final class CloudKitHelper {
    static let shared = CloudKitHelper()

    // MARK: - Published State

    private(set) var isSyncing = false
    private(set) var lastSyncDate: Date?
    private(set) var syncError: Error?
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
        // Listen for NSPersistentCloudKitContainer sync events.
        // The notification name is not publicly exposed as a constant,
        // so we use its string form.
        let eventNotification = Notification.Name("NSPersistentCloudKitContainerEventChangedNotification")
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
        // The userInfo contains a NSPersistentCloudKitContainer.Event.
        // We use KVC to extract the event properties without importing CoreData directly.
        guard let event = notification.userInfo?["event"] as? NSObject else { return }

        let didStart = (event.value(forKey: "startDate") as? Date) != nil
        let didEnd = (event.value(forKey: "endDate") as? Date) != nil
        let eventError = event.value(forKey: "error") as? Error

        if didStart && !didEnd {
            // Sync started
            isSyncing = true
            syncError = nil
            NotificationCenter.default.post(name: .cloudSyncDidBegin, object: nil)
        } else if didEnd {
            // Sync ended
            isSyncing = false
            if let error = eventError {
                syncError = error
                NotificationCenter.default.post(
                    name: .cloudSyncDidFail,
                    object: nil,
                    userInfo: ["error": error]
                )
            } else {
                lastSyncDate = Date()
                syncError = nil
                NotificationCenter.default.post(name: .cloudSyncDidComplete, object: nil)
            }
        }
    }

    // MARK: - Account Status

    func refreshSyncStatus() async {
        let status = await DataStorageManager.shared.cloudKitAccountStatus()
        isCloudKitAvailable = status != .noAccount && status != .couldNotDetermine
        isAccountConnected = status == .available
    }
}
