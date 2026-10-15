import Darwin
import Foundation
import SwiftData
import Testing
@testable import FinanceCore

/// Opt-in measurements, without hardware-dependent pass/fail thresholds.
@MainActor
struct PerformanceAuditTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test(.enabled(if: ProcessInfo.processInfo.environment["FORMI_PERFORMANCE_AUDIT"] == "1"))
    func planningAndSharingQueries() async throws {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let context = container.mainContext
        context.autosaveEnabled = false
        let a = Conto(name: "Selected", type: .checking, initialBalance: 20_000)
        let b = Conto(name: "Other", type: .checking)
        context.insert(a); context.insert(b)
        for index in 0..<2_500 {
            let row = Transaction(amount: Decimal(index % 173 + 1), type: .expense,
                date: now.addingTimeInterval(-Double(index % 500 + 1) * 86_400))
            row.notes = String(repeating: "x", count: 2_048)
            row.setFromConto(index < 500 ? a : b)
            context.insert(row)
        }
        let source = Transaction(amount: 10, type: .expense, date: now.addingTimeInterval(-700 * 86_400),
            isRecurring: true, recurrenceFrequency: .monthly)
        source.setFromConto(a); context.insert(source)
        try context.save()
        let calendar = Calendar.current
        let interval = calendar.dateInterval(of: .month, for: now)!
        let legacyContext = ModelContext(container)
        let all = try legacyContext.fetch(FetchDescriptor<Transaction>())
        let start = ContinuousClock.now
        var expected: [FinanceCalendarEvent] = []
        for _ in 0..<20 {
            expected = FinanceCalendarEvents.build(transactions: all, resolutions: [], contoIDs: [a.id], interval: interval, now: now)
            _ = Dictionary(grouping: expected) { calendar.startOfDay(for: $0.date) }
        }
        emit("calendar.20Rebuilds", count: all.count, start: start)
        let snapshotStart = ContinuousClock.now
        let snapshot = try await FinanceCalendarSnapshotReader().load(container: container, contoIDs: [a.id], interval: interval, now: now)
        for _ in 0..<20 { #expect(snapshot.presentation(expensesOnly: false, timeline: false).events == expected) }
        emit("calendar.snapshotAnd20Reads", count: all.count, start: snapshotStart)
        let forecastStart = ContinuousClock.now
        let old = MonthlyForecastCalculator.build(conto: a, transactions: all, resolutions: [], month: now, now: now)
        emit("forecast.calculation", count: all.count, start: forecastStart)
        let readerStart = ContinuousClock.now
        let report = try await MonthlyForecastSnapshotReader().load(container: container, contoID: a.id, month: now, now: now)
        emit("forecast.scopedReadAndCalculation", count: all.count, start: readerStart)
        #expect(report == old)
        let fullStart = ContinuousClock.now
        let fullContext = ModelContext(container)
        let full = try fullContext.fetch(FetchDescriptor<Transaction>())
        let fullIndex = Dictionary(uniqueKeysWithValues: full.map { ($0.id, $0) })
        let expectedIDs = Set(fullIndex.values.filter { $0.fromContoId == a.id || $0.toContoId == a.id }.map(\.id))
        emit("sharing.fullTransactionIndex", count: all.count, start: fullStart)
        let scopedStart = ContinuousClock.now
        let scopedContext = ModelContext(container)
        try SharedBookQueries.validateIdentities(in: scopedContext, key: \Transaction.id)
        let scoped = try SharedBookQueries.touching(contiIDs: [a.id], in: scopedContext)
        emit("sharing.identityScanAndScopedRead", count: all.count, start: scopedStart)
        #expect(Set(scoped.map(\.id)) == expectedIDs)
        print("PERF sharing scopedModels=\(scoped.count) archiveModels=\(full.count)")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["FORMI_PERFORMANCE_AUDIT"] == "1"))
    func syntheticBaseline() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        for count in [1_000, 10_000, 50_000] {
            let account = LedgerCacheAccount(id: UUID(), initialBalance: 1_000_000)
            let rows = (0..<count).map { index in
                TransactionSnapshot(amount: Decimal(index % 100 + 1), type: .expense,
                    date: now.addingTimeInterval(-Double(count - index) * 3_600), fromContoId: account.id)
            }
            let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
            let coordinator = LedgerCalculationCoordinator()
            let start = ContinuousClock.now
            let cold = try await coordinator.prepare(container: container, accounts: [account], transactions: rows,
                now: now, calendar: calendar)
            emit("ledger.cold", count: count, start: start)
            #expect(cold.snapshots[account.id]?.balance == 1_000_000 - rows.reduce(Decimal.zero) { $0 + $1.amount })
            for _ in 0..<3 {
                let start = ContinuousClock.now
                let warm = try await coordinator.prepare(container: container, accounts: [account], transactions: rows,
                    now: now, calendar: calendar)
                emit("ledger.memoryHit", count: count, start: start)
                #expect(warm.reusedCount == 1)
            }
            let saved = LedgerCacheAccount(id: account.id, initialBalance: account.initialBalance,
                ledgerCacheJSON: cold.updates[account.id])
            let diskStart = ContinuousClock.now
            let persisted = try LedgerCache.prepare(accounts: [saved], transactions: rows, now: now, calendar: calendar)
            emit("ledger.persistedHit", count: count, start: diskStart)
            #expect(persisted.reusedCount == 1)
            print("PERF payload count=\(count) bytes=\(cold.updates[account.id]?.utf8.count ?? 0) points=\(cold.snapshots[account.id]?.history.count ?? 0)")
        }

        for count in [100, 1_000] {
            let startDate = now.addingTimeInterval(-366 * 86_400)
            let movements = (0..<count).map { index in
                SavingsMovement(date: startDate.addingTimeInterval(Double(index) * 365 * 86_400 / Double(count)), amount: 10)
            }
            let rates = [SavingsRate(effectiveDate: startDate, annualPercent: 3)]
            let start = ContinuousClock.now
            var closing: SavingsValue?
            for day in 1...365 {
                closing = SavingsValuation.value(initialBalance: 1_000, start: startDate, rates: rates,
                    movements: movements, at: startDate.addingTimeInterval(Double(day) * 86_400), calendar: calendar)
            }
            emit("savings.365Samples", count: count, start: start)
            #expect(closing?.capital == Decimal(1_000 + count * 10))
            let dates = (1...365).map { startDate.addingTimeInterval(Double($0) * 86_400) }
            let seriesStart = ContinuousClock.now
            let series = SavingsValuation.values(initialBalance: 1_000, start: startDate, rates: rates,
                movements: movements, at: dates, calendar: calendar)
            emit("savings.365SamplesBatch", count: count, start: seriesStart)
            #expect(series.last == closing)
        }
        try queryBaseline()
    }

    private func queryBaseline() throws {
        // A temporary disk store exercises SQLite rather than an in-memory store.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("formi-performance-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = FinanceCoreModule.createSchema()
        let configuration = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("audit.store"),
            cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let writer = ModelContext(container)
        writer.autosaveEnabled = false
        let conto = Conto(name: "Synthetic", type: .checking)
        writer.insert(conto)
        for index in 0..<10_000 {
            let row = Transaction(amount: Decimal(index % 100 + 1), type: .expense,
                date: now.addingTimeInterval(-Double(index) * 3_600))
            row.setFromConto(conto)
            writer.insert(row)
        }
        try writer.save()
        let interval = DateInterval(start: now.addingTimeInterval(-366 * 86_400), end: now.addingTimeInterval(1))
        let query = TransactionListQuery(interval: interval, contoIDs: [conto.id])
        for _ in 0..<3 {
            let context = ModelContext(container)
            context.autosaveEnabled = false
            let start = ContinuousClock.now
            let page = try query.fetchPage(in: context, offset: 0, limit: 40)
            emit("query.page40", count: 10_000, start: start)
            #expect(page.count == 40)
            let summaryStart = ContinuousClock.now
            let summary = try query.summary(in: context)
            emit("query.periodSummary", count: 10_000, start: summaryStart)
            #expect(summary.count == 8_785)
        }
    }

    private func emit(_ name: String, count: Int, start: ContinuousClock.Instant) {
        let elapsed = start.duration(to: .now).components
        let ms = Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        print("PERF \(name) count=\(count) ms=\(String(format: "%.3f", ms)) processPeakMiB=\(String(format: "%.1f", Double(usage.ru_maxrss) / 1_048_576))")
    }
}
