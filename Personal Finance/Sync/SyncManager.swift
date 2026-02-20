//
//  SyncManager.swift
//  Personal Finance
//
//  Provides an observable sync generation counter that views can read
//  to automatically invalidate after each CloudKit sync cycle.
//

import Foundation
import Observation

@Observable
@MainActor
final class SyncManager {
    static let shared = SyncManager()

    /// Incremented after every successful sync or container change.
    /// Views that read this value will re-evaluate when sync completes.
    private(set) var syncGeneration: Int = 0

    private init() {
        let center = NotificationCenter.default
        center.addObserver(forName: .cloudSyncDidComplete, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.syncGeneration += 1
            }
        }
        center.addObserver(forName: .containerDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.syncGeneration += 1
            }
        }
    }
}
