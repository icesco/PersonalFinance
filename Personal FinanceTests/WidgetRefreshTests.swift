#if os(iOS)
import XCTest
import UIKit
import SwiftUI
import SwiftData
import FinanceCore
@testable import Personal_Finance

final class WidgetRefreshTests: XCTestCase {
    @MainActor
    func testSavedMovementTriggersSnapshotRefreshFromCommittedStore() async throws {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let initial = expectation(description: "Observer mounted")
        let updated = expectation(description: "Saved movement observed through a new context")
        var initialDelivered = false
        var updateDelivered = false
        let name = "widget-refresh-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let lock = AppLock(defaults: defaults)
        let observer = WidgetSnapshotObserver { source, protected in
            XCTAssertTrue(source === container)
            XCTAssertFalse(protected)
            let reader = ModelContext(source)
            let records = (try? reader.fetch(FetchDescriptor<FinanceTransaction>())) ?? []
            if records.isEmpty && !initialDelivered {
                initialDelivered = true
                initial.fulfill()
            }
            if records.first?.amount == Decimal(string: "12.34") && !updateDelivered {
                updateDelivered = true
                updated.fulfill()
            }
        }
        .environment(lock)
        .modelContainer(container)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: observer)
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        await fulfillment(of: [initial], timeout: 5)
        let record = FinanceTransaction(amount: Decimal(string: "12.34")!, type: .expense)
        container.mainContext.insert(record)
        try container.mainContext.save()
        await fulfillment(of: [updated], timeout: 5)
    }
}
#endif
