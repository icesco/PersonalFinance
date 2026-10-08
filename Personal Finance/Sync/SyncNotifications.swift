//
//  SyncNotifications.swift
//  Personal Finance
//
//  Notification names for cloud sync events.
//

import Foundation

extension Notification.Name {
    /// Posted once a grouped CloudKit session takes long enough to announce.
    static let cloudSyncDidBegin = Notification.Name("cloudSyncDidBegin")

    /// Posted when a CloudKit sync operation completes successfully.
    static let cloudSyncDidComplete = Notification.Name("cloudSyncDidComplete")

    /// Posted when a CloudKit sync operation fails.
    /// The notification's `userInfo` may contain an `"error"` key with the `Error`.
    static let cloudSyncDidFail = Notification.Name("cloudSyncDidFail")

    /// Posted when an unfinished session falls silent; does not indicate sync success.
    static let cloudSyncSessionDidEnd = Notification.Name("cloudSyncSessionDidEnd")

    /// Posted when the ModelContainer is recreated (e.g. after toggling iCloud sync).
    static let containerDidChange = Notification.Name("containerDidChange")
}
