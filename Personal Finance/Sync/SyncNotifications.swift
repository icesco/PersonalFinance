//
//  SyncNotifications.swift
//  Personal Finance
//
//  Notification names for cloud sync events.
//

import Foundation

extension Notification.Name {
    /// Posted when a CloudKit sync operation begins.
    static let cloudSyncDidBegin = Notification.Name("cloudSyncDidBegin")

    /// Posted when a CloudKit sync operation completes successfully.
    static let cloudSyncDidComplete = Notification.Name("cloudSyncDidComplete")

    /// Posted when a CloudKit sync operation fails.
    /// The notification's `userInfo` may contain an `"error"` key with the `Error`.
    static let cloudSyncDidFail = Notification.Name("cloudSyncDidFail")

    /// Posted when the ModelContainer is recreated (e.g. after toggling iCloud sync).
    static let containerDidChange = Notification.Name("containerDidChange")
}
