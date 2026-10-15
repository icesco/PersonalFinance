import Foundation
import SwiftData

public struct FinanceCalendarPresentation: Sendable {
    public let events: [FinanceCalendarEvent]
    public let byDay: [Date: [FinanceCalendarEvent]]

    init(events: [FinanceCalendarEvent], calendar: Calendar) {
        self.events = events
        byDay = Dictionary(grouping: events) { calendar.startOfDay(for: $0.date) }
    }
}

public struct FinanceCalendarSnapshot: Sendable {
    public let generatedAt: Date
    public let nextTransition: Date?
    private let all: FinanceCalendarPresentation
    private let expenses: FinanceCalendarPresentation
    private let upcoming: FinanceCalendarPresentation
    private let upcomingExpenses: FinanceCalendarPresentation

    init(events: [FinanceCalendarEvent], now: Date, calendar: Calendar) {
        generatedAt = now
        nextTransition = events.lazy.map(\.date).filter { $0 > now }.min()
        all = .init(events: events, calendar: calendar)
        expenses = .init(events: events.filter { $0.type == .expense }, calendar: calendar)
        let future = FinanceCalendarEvents.upcoming(events, now: now)
        upcoming = .init(events: future, calendar: calendar)
        upcomingExpenses = .init(events: future.filter { $0.type == .expense }, calendar: calendar)
    }

    public func presentation(expensesOnly: Bool, timeline: Bool) -> FinanceCalendarPresentation {
        timeline ? (expensesOnly ? upcomingExpenses : upcoming) : (expensesOnly ? expenses : all)
    }
}

public actor FinanceCalendarSnapshotReader {
    public init() {}

    public func load(container: ModelContainer, contoIDs: Set<UUID>, interval: DateInterval,
                     now: Date = Date(), calendar: Calendar = .current) throws -> FinanceCalendarSnapshot {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return try Self.read(in: context, contoIDs: contoIDs, interval: interval, now: now, calendar: calendar)
    }

    /// Synchronous entry point for callers that own a context with unsaved edits.
    nonisolated public static func read(in context: ModelContext, contoIDs: Set<UUID>, interval: DateInterval,
                                       now: Date = Date(), calendar: Calendar = .current) throws -> FinanceCalendarSnapshot {
        try Task.checkCancellation()
        guard !contoIDs.isEmpty else { return .init(events: [], now: now, calendar: calendar) }
        let ids = Array(contoIDs)
        let start = interval.start, end = interval.end
        let fromScope = #Predicate<Transaction> { row in
            row.fromContoId.flatMap { id in ids.contains(id) } ?? false
        }
        let toScope = #Predicate<Transaction> { row in
            row.toContoId.flatMap { id in ids.contains(id) } ?? false
        }
        let relevant = #Predicate<Transaction> { row in
            row.isRecurring == true || (row.date >= start && row.date < end) || row.recurrenceSourceID != nil
        }
        var descriptor = FetchDescriptor<Transaction>(predicate: #Predicate<Transaction> { row in
            (fromScope.evaluate(row) || toScope.evaluate(row)) && relevant.evaluate(row)
        })
        descriptor.relationshipKeyPathsForPrefetching = [\.category]
        let rows = try context.fetch(descriptor)
        let sourceIDs = Array(Set(rows.filter { $0.isRecurring == true }.map(\.id)))
        let resolutions = try PlanningSnapshotQueries.resolutions(in: context, sourceIDs: sourceIDs)
        try Task.checkCancellation()
        let events = FinanceCalendarEvents.build(transactions: rows, resolutions: resolutions,
            contoIDs: contoIDs, interval: interval, now: now)
        try Task.checkCancellation()
        return .init(events: events, now: now, calendar: calendar)
    }
}

public actor MonthlyForecastSnapshotReader {
    public enum Failure: Error { case missingAccount }
    public init() {}

    public func load(container: ModelContainer, contoID: UUID, month: Date,
                     now: Date = Date(), calendar: Calendar = .current) throws -> MonthlyForecast {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return try Self.read(in: context, contoID: contoID, month: month, now: now, calendar: calendar)
    }

    nonisolated public static func read(in context: ModelContext, contoID: UUID, month: Date,
                                       now: Date = Date(), calendar: Calendar = .current) throws -> MonthlyForecast {
        try Task.checkCancellation()
        var account = FetchDescriptor<Conto>(predicate: #Predicate { $0.id == contoID })
        account.fetchLimit = 1
        guard let conto = try context.fetch(account).first else { throw Failure.missingAccount }
        // Full account history is required for balance, provenance, category evidence and freshness.
        var descriptor = FetchDescriptor<Transaction>(predicate: #Predicate<Transaction> {
            $0.fromContoId == contoID || $0.toContoId == contoID
        })
        descriptor.relationshipKeyPathsForPrefetching = [\.category]
        let rows = try context.fetch(descriptor)
        let sourceIDs = Array(Set(rows.filter { $0.isRecurring == true }.map(\.id)))
        let resolutions = try PlanningSnapshotQueries.resolutions(in: context, sourceIDs: sourceIDs)
        try Task.checkCancellation()
        let budgets = try context.fetch(FetchDescriptor<Budget>(predicate: #Predicate { $0.contoID == contoID && $0.isActive == true }))
        let value = MonthlyForecastCalculator.build(conto: conto, transactions: rows, resolutions: resolutions,
            month: month, now: now, calendar: calendar, budgets: budgets)
        try Task.checkCancellation()
        return value
    }
}

enum PlanningSnapshotQueries {
    static func resolutions(in context: ModelContext, sourceIDs: [UUID]) throws -> [RecurrenceResolution] {
        guard !sourceIDs.isEmpty else { return [] }
        return try context.fetch(FetchDescriptor<RecurrenceResolution>(predicate: #Predicate { sourceIDs.contains($0.sourceID) }))
    }
}
