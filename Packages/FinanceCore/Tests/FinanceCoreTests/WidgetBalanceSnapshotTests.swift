import Foundation
import Testing
@testable import FinanceCore

@MainActor
struct WidgetBalanceSnapshotTests {
    @Test func sharedInputsMatchStandalonePeriodsAcrossYearBoundary() throws {
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 12, day: 30, hour: 12)))
        let books = [Account(name: "A"), Account(name: "B")]
        let conti = [Conto(name: "Savings", type: .savings, initialBalance: 1_000),
                     Conto(name: "Bank", type: .checking, initialBalance: 2_000)]
        for index in 0..<2 { books[index].conti = [conti[index]]; conti[index].account = books[index] }
        try conti[0].setSavingsRate(5, effectiveDate: now.addingTimeInterval(-366 * 86_400))
        let source = Transaction(amount: 10, type: .expense, date: now.addingTimeInterval(-7 * 86_400),
            isRecurring: true, recurrenceFrequency: .daily)
        source.setFromConto(conti[0])
        let transfer = Transaction(amount: 20, type: .transfer, date: now.addingTimeInterval(3 * 86_400))
        transfer.setFromConto(conti[0]); transfer.setToConto(conti[1]); transfer.destinationAmount = 18
        let rows = [source, transfer]
        let ledger = try LedgerCache.prepare(conti: conti, transactions: rows, now: now, calendar: calendar).snapshots
        let shared = FinanceWidgetBuilder.build(accounts: books, budgets: [], transactions: rows,
            resolutions: [], now: now, calendar: calendar, ledgerSnapshots: ledger)
        for index in 0..<2 {
            let book = try #require(shared.books.first { $0.id == books[index].id })
            for period in WidgetBalancePeriod.allCases {
                let actual = try #require(book.balanceHistories?.first { $0.period == period })
                let expected = WidgetBalanceSnapshot.make(period: period, conti: [conti[index]], transactions: rows,
                    resolutions: [], now: now, calendar: calendar, ledgerSnapshots: ledger)
                #expect(actual.interval == expected.interval)
                #expect(actual.recordedTotal == expected.recordedTotal)
                #expect(actual.projectedTotal == expected.projectedTotal)
                #expect(actual.plannedMovements == expected.plannedMovements)
                #expect(actual.scheduledFlowGroups == expected.scheduledFlowGroups)
                #expect(actual.series.map { $0.points.map(\.balance) } == expected.series.map { $0.points.map(\.balance) })
                #expect(actual.series.map { $0.projected.map(\.date) } == expected.series.map { $0.projected.map(\.date) })
                #expect(actual.series.map { $0.projected.map(\.balance) } == expected.series.map { $0.projected.map(\.balance) })
            }
        }
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome")!
        calendar.firstWeekday = 2
        return calendar
    }
    private func date(_ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    @Test func allPeriodsKeepAccountBalancesTransfersAndProjectionsSeparate() throws {
        let book = Account(name: "Euro", currency: "EUR")
        let a = Conto(name: "Corrente", type: .checking, initialBalance: 100)
        let b = Conto(name: "Risparmi", type: .savings, initialBalance: 50)
        book.conti = [a, b]; a.account = book; b.account = book
        let recorded = Transaction(amount: 20, type: .transfer, date: date(2))
        recorded.setFromConto(a); recorded.setToConto(b)
        let scheduled = Transaction(amount: 10, type: .transfer, date: date(9))
        scheduled.setFromConto(a); scheduled.setToConto(b)
        let income = Transaction(amount: 200, type: .income, date: date(10))
        income.setToConto(a)
        let snapshot = FinanceWidgetBuilder.build(accounts: [book], budgets: [], transactions: [recorded, scheduled, income],
                                                  resolutions: [], now: date(7), calendar: calendar)
        let histories = try #require(snapshot.books.first?.balanceHistories)
        #expect(Set(histories.map(\.period)) == Set(WidgetBalancePeriod.allCases))
        #expect(histories.allSatisfy { $0.recordedTotal == 150 && $0.projectedTotal == 350 })
        for history in histories {
            #expect(history.series.first { $0.id == a.id }?.balance(at: date(7)) == 80)
            #expect(history.series.first { $0.id == b.id }?.balance(at: date(7)) == 70)
            #expect(history.series.first { $0.id == a.id }?.balance(at: history.interval.end) == 270)
            #expect(history.series.first { $0.id == b.id }?.balance(at: history.interval.end) == 80)
            #expect(history.interval == history.period.interval(containing: date(7), calendar: calendar))
        }
        #expect(!snapshot.usable(at: snapshot.validUntil))
        #expect(snapshot.validUntil <= histories.map(\.interval.end).min()!)
    }

    @Test func creditPaymentsAreTransfersAndCreditLimitIsNotCash() {
        let bank = Conto(name: "Corrente", type: .checking, initialBalance: 2000)
        let card = Conto(name: "Carta", type: .credit, initialBalance: -300, creditLimit: 5000)
        let payment = Transaction(amount: 300, type: .transfer, date: date(9))
        payment.setFromConto(bank); payment.setToConto(card)
        let expense = Transaction(amount: 100, type: .expense, date: date(10))
        expense.setFromConto(card)
        let income = Transaction(amount: 200, type: .income, date: date(11))
        income.setToConto(bank)
        let history = WidgetBalanceSnapshot.make(period: .month, conti: [bank, card],
            transactions: [payment, expense, income], resolutions: [], now: date(7), calendar: calendar)
        #expect(history.recordedTotal == 1700)
        #expect(history.projectedTotal == 1800)
        #expect(history.scheduledFlows?.incoming == 200)
        #expect(history.scheduledFlows?.outgoing == 100)
        #expect(history.plannedMovements?.count == 3)
        let bankOnly = history.selecting(accountIDs: [bank.id])
        #expect(bankOnly.projectedTotal == 1900)
        #expect(bankOnly.scheduledFlows?.incoming == 200)
        #expect(bankOnly.scheduledFlows?.outgoing == 300)
        #expect(bankOnly.plannedMovements?.count == 2)
        let cardOnly = history.selecting(accountIDs: [card.id])
        #expect(cardOnly.projectedTotal == -100)
        #expect(cardOnly.scheduledFlows?.incoming == 300)
        #expect(cardOnly.scheduledFlows?.outgoing == 100)
        let flat = WidgetBalanceSnapshot.make(period: .month, conti: [bank, card],
            transactions: [], resolutions: [], now: date(7), calendar: calendar)
        #expect(flat.projectedTotal == 1700)
        #expect(flat.plannedMovements?.isEmpty == true)
    }

    @Test func savingsRateDoesNotAddEstimatedInterestToLedgerForecast() throws {
        let savings = Conto(name: "Risparmi", type: .savings, initialBalance: 1000)
        try savings.setSavingsRate(10, effectiveDate: date(1))
        let credited = Transaction(amount: 5, type: .income, date: date(3))
        credited.isSavingsInterest = true; credited.setToConto(savings)
        let futureCredit = Transaction(amount: 10, type: .income, date: date(20))
        futureCredit.isSavingsInterest = true; futureCredit.setToConto(savings)
        let history = WidgetBalanceSnapshot.make(period: .month, conti: [savings],
            transactions: [credited, futureCredit, futureCredit], resolutions: [], now: date(7), calendar: calendar)
        #expect(history.recordedTotal == 1005)
        #expect(history.projectedTotal == 1015)
        #expect(history.scheduledFlows?.incoming == 10)
        #expect(history.scheduledFlows?.outgoing == 0)
        #expect(history.plannedMovements?.count == 1)
        #expect(history.series.first?.savingsValue == nil)
    }

    @Test func scheduledDetailsCoverWholePeriodAndLegacyCacheRemainsReadable() throws {
        let bank = Conto(name: "Corrente", type: .checking, initialBalance: 1000)
        let anchor = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12))!
        let now = calendar.date(from: DateComponents(year: 2026, month: 1, day: 7, hour: 12))!
        let expense = Transaction(amount: 10, type: .expense, date: anchor, isRecurring: true, recurrenceFrequency: .monthly)
        expense.transactionDescription = "Abbonamento"; expense.setFromConto(bank)
        let annual = WidgetBalanceSnapshot.make(period: .year, conti: [bank], transactions: [expense],
            resolutions: [], now: now, calendar: calendar)
        #expect(annual.plannedMovements?.count == 3)
        #expect(annual.scheduledMovementCount == 11)
        #expect(annual.scheduledFlows?.outgoing == 110)
        #expect(annual.projectedTotal - annual.recordedTotal == -110)
        #expect(Set(annual.plannedMovements?.map(\.id) ?? []).count == 3)
        let quarter = WidgetBalanceSnapshot.make(period: .quarter, conti: [bank], transactions: [expense],
            resolutions: [], now: now, calendar: calendar)
        #expect(quarter.plannedMovements?.count == 2)
        #expect(quarter.scheduledFlows?.outgoing == 20)
        let data = try JSONEncoder().encode(annual)
        #expect(try JSONDecoder().decode(WidgetBalanceSnapshot.self, from: data) == annual)
        var legacy = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "plannedMovements")
        legacy.removeValue(forKey: "scheduledFlowGroups")
        let decoded = try JSONDecoder().decode(WidgetBalanceSnapshot.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(decoded.plannedMovements == nil)
        #expect(decoded.scheduledFlows == nil)
        #expect(decoded.projectedTotal == annual.projectedTotal)
    }

    @Test func boundedScadenzeKeepTotalsAndNextRowsForEachSelection() {
        let a = Conto(name: "A", type: .checking, initialBalance: 100)
        let b = Conto(name: "B", type: .checking, initialBalance: 100)
        let rows = (8...20).flatMap { day in
            [a, b].map { account in
                let row = Transaction(amount: 1, type: .expense, date: date(day))
                row.setFromConto(account)
                return row
            }
        }
        let history = WidgetBalanceSnapshot.make(period: .month, conti: [a, b], transactions: rows,
            resolutions: [], now: date(7), calendar: calendar)
        #expect(history.plannedMovements?.count == 6)
        #expect(history.scheduledMovementCount == 26)
        #expect(history.scheduledFlows?.outgoing == 26)
        let selected = history.selecting(accountIDs: [b.id])
        #expect(selected.scheduledMovementCount == 13)
        #expect(selected.scheduledFlows?.outgoing == 13)
        #expect(selected.plannedMovements?.map(\.date) == [date(8), date(9), date(10)])
        #expect(selected.projectedTotal == 87)
    }

    @Test func unknownScheduledAmountsAreNotShownAsCompleteTotals() {
        let bank = Conto(name: "Banca", type: .checking, initialBalance: 100)
        let unknown = Transaction(amount: 0, type: .expense, date: date(9))
        unknown.amount = nil
        unknown.setFromConto(bank)
        let history = WidgetBalanceSnapshot.make(period: .month, conti: [bank], transactions: [unknown],
            resolutions: [], now: date(7), calendar: calendar)
        #expect(history.plannedMovements?.count == 1)
        #expect(history.plannedMovements?.first?.amount == nil)
        #expect(history.scheduledFlows?.incoming == nil)
        #expect(history.scheduledFlows?.outgoing == nil)
    }

    @Test func groupingDoesNotNetOffOppositeSignedMovements() {
        let bank = Conto(name: "Banca", type: .checking, initialBalance: 100)
        let expense = Transaction(amount: 20, type: .expense, date: date(9))
        expense.setFromConto(bank)
        let reversal = Transaction(amount: -5, type: .expense, date: date(10))
        reversal.setFromConto(bank)
        let history = WidgetBalanceSnapshot.make(period: .month, conti: [bank], transactions: [expense, reversal],
            resolutions: [], now: date(7), calendar: calendar)
        #expect(history.scheduledFlows?.incoming == 5)
        #expect(history.scheduledFlows?.outgoing == 20)
        #expect(history.projectedTotal == 85)
    }

    @Test func persistedChartRoundTripsAndLegacySnapshotsStillDecode() throws {
        let book = Account(name: "Libro")
        let conto = Conto(name: "Banca", type: .checking, initialBalance: 125)
        conto.account = book; book.conti = [conto]
        let snapshot = FinanceWidgetBuilder.build(accounts: [book], budgets: [], transactions: [], resolutions: [], now: date(7), calendar: calendar)
        let data = try JSONEncoder().encode(snapshot)
        #expect(try JSONDecoder().decode(FinanceWidgetSnapshot.self, from: data) == snapshot)
        var legacy = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var books = try #require(legacy["books"] as? [[String: Any]])
        books[0].removeValue(forKey: "balanceHistories")
        legacy["books"] = books
        let decoded = try JSONDecoder().decode(FinanceWidgetSnapshot.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(decoded.books.first?.balanceHistories == nil)
        #expect(decoded.usable(at: date(7)))
        #expect(FinanceWidgetSnapshot.empty(.hidden).books.isEmpty)
    }

    @Test func futureMovementDaysSurviveEvenWhenDailyNetChangeIsZero() throws {
        let bank = Conto(name: "Banca", type: .checking, initialBalance: 100)
        let other = Conto(name: "Altro", type: .checking, initialBalance: 50)
        let expense = Transaction(amount: 20, type: .expense, date: date(9, hour: 9))
        expense.setFromConto(bank)
        let income = Transaction(amount: 20, type: .income, date: date(9, hour: 18))
        income.setToConto(bank)
        let nextExpense = Transaction(amount: 5, type: .expense, date: date(10))
        nextExpense.setFromConto(bank)
        let history = WidgetBalanceSnapshot.make(period: .month, conti: [bank, other],
            transactions: [expense, income, nextExpense], resolutions: [], now: date(7), calendar: calendar)
        let projected = try #require(history.series.first { $0.id == bank.id }?.projected)
        let movementPoints = projected.filter { $0.date > history.recordedAt && $0.date < history.interval.end }
        #expect(movementPoints.map(\.date) == [date(9, hour: 18), date(10)])
        #expect(movementPoints.map(\.balance) == [100, 95])
        let unrelated = try #require(history.series.first { $0.id == other.id }?.projected)
        #expect(unrelated.filter { $0.date > history.recordedAt && $0.date < history.interval.end }.isEmpty)
        #expect(history.totalProjected.contains { $0.date == date(9, hour: 18) && $0.balance == 150 })
        #expect(history.selecting(accountIDs: [other.id]).totalProjected.count == 2)
    }

    @Test func projectedMinimumUsesDailyTotalsRatherThanPartialAccountClosings() {
        let interval = DateInterval(start: date(1), end: date(31))
        let a = AccountBalanceSeries(id: UUID(), name: "A", colorHex: "356CB0",
            points: [.init(date: date(7), balance: 100)],
            projected: [.init(date: date(7), balance: 100), .init(date: date(9, hour: 9), balance: 0),
                        .init(date: interval.end, balance: 0)])
        let b = AccountBalanceSeries(id: UUID(), name: "B", colorHex: "8E5A88",
            points: [.init(date: date(7), balance: 100)],
            projected: [.init(date: date(7), balance: 100), .init(date: date(9, hour: 18), balance: 200),
                        .init(date: interval.end, balance: 200)])
        let history = WidgetBalanceSnapshot(period: .month, interval: interval, recordedAt: date(7), series: [a, b])
        #expect(history.minimumProjectedDailyBalance(calendar: calendar)?.balance == 200)
        #expect(history.minimumProjectedDailyBalance(calendar: calendar)?.date == date(9, hour: 18))
        #expect(history.selecting(accountIDs: [a.id]).minimumProjectedDailyBalance(calendar: calendar)?.balance == 0)
        let empty = WidgetBalanceSnapshot(period: .month, interval: interval, recordedAt: date(7), series: [])
        #expect(empty.minimumProjectedDailyBalance(calendar: calendar) == nil)
    }

    @Test func dailySnapshotsRemainBoundedAndColorsMatchTheApp() throws {
        let bank = Conto(name: "Banca", type: .checking, initialBalance: 1000)
        let other = Conto(name: "Altro", type: .checking, initialBalance: 10)
        let values = (0..<1000).map { index in
            let transaction = Transaction(amount: 1, type: .expense, date: date(2, hour: 0).addingTimeInterval(Double(index)))
            transaction.setFromConto(bank)
            return transaction
        }
        let history = WidgetBalanceSnapshot.make(period: .month, conti: [bank, other], transactions: values,
                                                   resolutions: [], now: date(7), calendar: calendar)
        let app = AccountBalanceSeries.make(conti: [bank, other], selectedIDs: [bank.id, other.id], transactions: values,
                                             resolutions: [], interval: history.interval, now: date(7))
        #expect(history.series.allSatisfy { $0.points.count <= 4 })
        #expect(history.recordedTotal == 10)
        #expect(history.projectedTotal == 10)
        #expect(history.series.map(\.colorHex) == app.map(\.colorHex))
        #expect(history.series.map { $0.balance(at: date(7)) } == app.map { $0.balance(at: date(7)) })
    }

    @Test func balanceLinkRoundTripsToAnalysis() {
        let route = FinanceWidgetRoute(destination: .analysis, bookID: UUID())
        #expect(FinanceWidgetRoute(url: route.url) == route)
    }

    @Test func totalCurveKeepsEveryChangeAndCancelsTransfers() {
        let first = AccountBalanceSeries(id: UUID(), name: "Banca", colorHex: "356CB0",
            points: [.init(date: date(1), balance: 100), .init(date: date(3), balance: 80),
                     .init(date: date(7), balance: 80)],
            projected: [.init(date: date(7), balance: 80), .init(date: date(9), balance: 70),
                        .init(date: date(31), balance: 70)])
        let second = AccountBalanceSeries(id: UUID(), name: "Risparmi", colorHex: "7354A6",
            points: [.init(date: date(1), balance: 50), .init(date: date(3), balance: 70),
                     .init(date: date(5), balance: 75), .init(date: date(7), balance: 75)],
            projected: [.init(date: date(7), balance: 75), .init(date: date(9), balance: 85),
                        .init(date: date(10), balance: 285), .init(date: date(31), balance: 285)])
        let debt = AccountBalanceSeries(id: UUID(), name: "Carta", colorHex: "A5532B",
            points: [.init(date: date(1), balance: -30), .init(date: date(7), balance: -30)], projected: [])
        let history = WidgetBalanceSnapshot(period: .month,
            interval: DateInterval(start: date(1), end: date(31)), recordedAt: date(7), series: [first, second, debt])
        #expect(history.totalPoints.map(\.date) == [date(1), date(3), date(5), date(7)])
        #expect(history.totalPoints.map(\.balance) == [120, 120, 125, 125])
        #expect(history.totalProjected.map(\.balance) == [125, 125, 325, 325])
        #expect(history.totalPoints.last?.balance == history.recordedTotal)
        #expect(history.totalProjected.first?.balance == history.recordedTotal)
        #expect(history.totalProjected.last?.balance == history.projectedTotal)
    }

    @Test func totalCurveWithoutProjectionDoesNotInventAForecast() {
        let series = AccountBalanceSeries(id: UUID(), name: "Conto", colorHex: "356CB0",
            points: [.init(date: date(1), balance: 50), .init(date: date(7), balance: 50)], projected: [])
        let history = WidgetBalanceSnapshot(period: .month,
            interval: DateInterval(start: date(1), end: date(31)), recordedAt: date(7), series: [series])
        #expect(history.totalPoints.map(\.balance) == [50, 50])
        #expect(history.totalProjected.isEmpty)
        let empty = WidgetBalanceSnapshot(period: .month, interval: history.interval, recordedAt: date(7), series: [])
        #expect(empty.totalPoints.isEmpty)
        #expect(empty.totalProjected.isEmpty)
    }

    @Test func accountSelectionScopesBalancesAndKeepsIdentityAndPeriod() {
        let a = AccountBalanceSeries(id: UUID(), name: "Banca", colorHex: "356CB0",
            points: [.init(date: date(7), balance: 100)], projected: [.init(date: date(31), balance: 80)])
        let b = AccountBalanceSeries(id: UUID(), name: "Carta", colorHex: "8E5A88",
            points: [.init(date: date(7), balance: -30)], projected: [])
        let history = WidgetBalanceSnapshot(period: .month,
            interval: DateInterval(start: date(1), end: date(31)), recordedAt: date(7), series: [a, b])
        #expect(history.selecting(accountIDs: []) == history)
        #expect(history.selecting(accountIDs: [a.id, b.id]) == history)
        let selected = history.selecting(accountIDs: [a.id])
        #expect(selected.series == [a])
        #expect(selected.recordedTotal == 100)
        #expect(selected.projectedTotal == 80)
        #expect(selected.period == history.period && selected.interval == history.interval)
        #expect(selected.recordedAt == history.recordedAt)
        #expect(history.selecting(accountIDs: [UUID()]).series.isEmpty)
        #expect(history.selecting(accountIDs: [b.id, UUID()]).series == [b])
    }
}
