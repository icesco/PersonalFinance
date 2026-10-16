import Foundation
import SwiftData
import Testing
@testable import FinanceCore

@MainActor
struct MovementHeatmapTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Rome")!
        return value
    }
    private func date(_ day: Int, month: Int = 10, hour: Int = 12) -> Date {
        calendar.date(from: .init(year: 2026, month: month, day: day, hour: hour))!
    }
    private func row(_ type: TransactionType, _ amount: Decimal, day: Int, from: Conto? = nil, to: Conto? = nil) -> FinanceCore.Transaction {
        let row = FinanceCore.Transaction(amount: amount, type: type, date: date(day))
        row.setFromConto(from); row.setToConto(to)
        return row
    }

    @Test func scopesEachMovementByItsFinancialEndpointAndCountsTransfersOnce() throws {
        let bank = Conto(name: "Corrente", type: .checking), joint = Conto(name: "Cointestato", type: .checking)
        let foreign = Conto(name: "Privato", type: .checking)
        let salary = row(.income, 1000, day: 1, to: bank)
        let groceries = row(.expense, 80, day: 2, from: joint)
        let coffee = row(.expense, 5, day: 2, from: bank)
        let transfer = row(.transfer, 300, day: 3, from: bank, to: joint)
        let outside = row(.expense, 999, day: 2, from: foreign)
        let wrongEndpoint = row(.expense, 999, day: 2, from: foreign, to: bank)
        let wrongIncome = row(.income, 999, day: 2, from: bank, to: foreign)
        let values = [salary, groceries, coffee, transfer, outside, wrongEndpoint, wrongIncome, transfer, coffee]
        func report(_ ids: Set<UUID>) -> MovementHeatmapMonth {
            .build(transactions: values, contoIDs: ids, month: date(1), now: date(16), calendar: calendar)
        }
        let all = report([bank.id, joint.id])
        #expect(all.totals.income == 1000 && all.totals.expenses == 85 && all.totals.net == 915)
        #expect(all.days[2].entries.count == 1 && all.days[2].onlyTransfers)
        #expect(report([bank.id]).totals.expenses == 5)
        #expect(report([joint.id]).totals.expenses == 80)
        #expect(report([joint.id]).days[2].entries.count == 1)
        #expect(report([]).isEmpty)
    }

    @Test func keepsEmptyBalancedAndTransferOnlyDaysDistinctWithoutProjectingRecurrences() throws {
        let bank = Conto(name: "Corrente", type: .checking), savings = Conto(name: "Riserva", type: .savings)
        let incoming = row(.income, 75, day: 8, to: bank)
        let outgoing = row(.expense, 75, day: 8, from: bank)
        let transfer = row(.transfer, 100, day: 12, from: bank, to: savings)
        let future = row(.expense, 500, day: 20, from: bank)
        let recurring = row(.expense, 10, day: 1, from: bank)
        recurring.isRecurring = true; recurring.recurrenceFrequency = .daily
        let previous = row(.expense, 999, day: 30, from: bank); previous.date = date(30, month: 9)
        let boundary = row(.expense, 999, day: 1, from: bank); boundary.date = date(1, month: 11, hour: 0)
        let value = MovementHeatmapMonth.build(transactions: [incoming, outgoing, transfer, future, recurring, previous, boundary],
            contoIDs: [bank.id, savings.id], month: date(1), now: date(16), calendar: calendar)
        #expect(value.days.count == 31)
        #expect(value.days[7].hasBalancedActivity && value.days[7].totals.net == 0)
        #expect(value.days[9].isEmpty && !value.days[9].hasBalancedActivity)
        #expect(value.days[11].onlyTransfers && value.days[11].totals.net == 0)
        #expect(value.days[19].isFuture && value.days[19].isEmpty)
        #expect(value.totals.expenses == 85)
    }

    @Test func handlesDSTLegacyRelationshipsRefundsAndInvalidAmounts() throws {
        let bank = Conto(name: "Banca", type: .checking)
        let first = row(.expense, 100, day: 24, from: bank)
        let refund = row(.expense, -20, day: 24, from: bank)
        first.fromContoId = nil; refund.fromContoId = nil
        let invalid = row(.income, 30, day: 25, to: bank); invalid.amount = .nan
        let value = MovementHeatmapMonth.build(transactions: [first, refund, invalid], contoIDs: [bank.id],
            month: date(1), now: date(31), calendar: calendar)
        #expect(value.totals.expenses == 80 && value.totals.income == nil && value.totals.net == nil)
        #expect(value.days[23].totals.expenses == 80)
        #expect(value.days[24].entries.first?.amount == nil)
        #expect(value.days[25].date.timeIntervalSince(value.days[24].date) == 25 * 3600)
        #expect(Set(value.days.map(\.date)).count == 31)
        #expect(MovementHeatmapMode.expense.level(in: value.days[23].totals) == 2)
    }

    @Test func readerSeparatesCurrenciesIncludesArchivedContiAndUsesDestinationTransferAmount() async throws {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let context = container.mainContext
        let euro = Account(name: "EUR", currency: "EUR"), dollar = Account(name: "USD", currency: "USD")
        context.insert(euro); context.insert(dollar)
        let bank = Conto(name: "Euro", type: .checking), foreign = Conto(name: "Dollari", type: .checking)
        bank.account = euro; bank.isActive = false; foreign.account = dollar
        context.insert(bank); context.insert(foreign)
        let expense = row(.expense, 20, day: 2, from: bank)
        let other = row(.expense, 900, day: 2, from: foreign)
        let transfer = row(.transfer, 110, day: 3, from: foreign, to: bank)
        transfer.destinationAmount = 100
        for row in [expense, other, transfer] { context.insert(row) }
        try context.save()
        expense.fromContoId = nil; try context.save()
        let reader = MovementHeatmapReader()
        let result = try await reader.load(container: container, contoIDs: [bank.id, foreign.id], currency: "EUR",
            month: date(1), now: date(16), calendar: calendar)
        #expect(result.totals.expenses == 20)
        #expect(result.days[2].entries.first?.amount == 100)
        #expect(result.days[2].entries.first?.accountName == nil)
        #expect(result.days[2].entries.first?.destinationName == "Euro")
        #expect(result.days.flatMap(\.entries).count == 2)
        let absent = try await reader.load(container: container, contoIDs: [UUID()], currency: "EUR",
            month: date(1), now: date(16), calendar: calendar)
        #expect(absent.isEmpty)
        expense.amount = 25
        let draft = try MovementHeatmapReader.read(in: context, contoIDs: [bank.id], currency: "EUR",
            month: date(1), now: date(16), calendar: calendar)
        #expect(draft.totals.expenses == 25 && context.hasChanges)
    }
}
