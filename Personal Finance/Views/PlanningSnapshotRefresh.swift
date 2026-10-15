import SwiftUI
import SwiftData
import FinanceCore
import CoreData

struct PlanningSnapshotScope: Equatable {
    let container: ObjectIdentifier
    let ids: Set<UUID>
    let interval: DateInterval
    let calendar: String
    let timeZone: String

    init(container: ModelContainer, ids: Set<UUID>, month: Date) {
        self.container = ObjectIdentifier(container)
        self.ids = ids
        let calendar = Calendar.current
        interval = calendar.dateInterval(of: .month, for: month)!
        self.calendar = String(describing: calendar.identifier)
        timeZone = calendar.timeZone.identifier
    }
}

struct PlanningSnapshotRequest: Equatable {
    let scope: PlanningSnapshotScope
    let revision: Int
}

struct PlanningSnapshotRefresh: ViewModifier {
    let contoIDs: Set<UUID>
    @Binding var revision: Int
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var phase

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: FinanceDataChangeCenter.notificationName).receive(on: RunLoop.main)) {
                guard let change = FinanceDataChange.from($0), change.affects(container: context.container, contoIDs: contoIDs) else { return }
                revision &+= 1
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange).receive(on: RunLoop.main)) { _ in revision &+= 1 }
            .onReceive(NotificationCenter.default.publisher(for: .cloudSyncDidComplete).receive(on: RunLoop.main)) { _ in revision &+= 1 }
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange).receive(on: RunLoop.main)) { _ in revision &+= 1 }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in revision &+= 1 }
            .onChange(of: phase) { _, phase in if phase == .active { revision &+= 1 } }
            .task {
                do {
                    while !Task.isCancelled {
                        try await Task.sleep(for: .seconds(60))
                        if phase == .active { revision &+= 1 }
                    }
                } catch {}
            }
    }
}

/// Only the sources of displayed events are materialized for navigation and category styling.
struct PlanningEventTransactions<Content: View>: View {
    @Query private var transactions: [FinanceCore.Transaction]
    let content: ([FinanceCore.Transaction]) -> Content

    init(events: [FinanceCalendarEvent], @ViewBuilder content: @escaping ([FinanceCore.Transaction]) -> Content) {
        let ids = Array(Set(events.map(\.transactionID)))
        _transactions = Query(filter: #Predicate<FinanceCore.Transaction> { ids.contains($0.id) })
        self.content = content
    }

    var body: some View { content(transactions) }
}
