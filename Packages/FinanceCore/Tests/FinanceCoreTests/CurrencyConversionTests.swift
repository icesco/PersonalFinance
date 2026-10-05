import Foundation
import Testing
@testable import FinanceCore

struct CurrencyConversionTests {
    @Test func crossRateAndRounding() throws {
        let snapshot = CurrencyRateSnapshot(day: "2026-10-02", perEuro: ["USD": 2, "GBP": 1])
        #expect(try snapshot.rate(from: "USD", to: "GBP") == Decimal(string: "0.5"))
        #expect(try CurrencyConversion.convert(10, rate: snapshot.rate(from: "USD", to: "EUR"), currency: "EUR") == 5)
        #expect(try CurrencyConversion.convert(100, rate: Decimal(string: "1.005")!, currency: "EUR") == Decimal(string: "100.50"))
        #expect(try CurrencyConversion.convert(100, rate: Decimal(string: "1.006")!, currency: "JPY") == 101)
        #expect(throws: CurrencyConversion.Failure.unsupported) { try snapshot.rate(from: "XXX", to: "EUR") }
        #expect(throws: CurrencyConversion.Failure.invalid) { try CurrencyConversion.convert(10, rate: 0, currency: "EUR") }
    }
    @Test func parsesDatedRatesWithoutMixingDays() throws {
        let xml = """
        <Envelope><Cube><Cube time="2026-10-01"><Cube currency="USD" rate="1.1"/></Cube><Cube time="2026-10-02"><Cube currency="USD" rate="1.2"/><Cube currency="JPY" rate="150"/></Cube></Cube></Envelope>
        """
        let snapshots = try CurrencyConversion.parseECB(Data(xml.utf8))
        #expect(snapshots.map(\.day) == ["2026-10-02", "2026-10-01"])
        #expect(snapshots[0].perEuro["USD"] == Decimal(string: "1.2"))
        #expect(snapshots[1].perEuro["JPY"] == nil)
        #expect(throws: CurrencyConversion.Failure.invalidFeed) { try CurrencyConversion.parseECB(Data("not XML".utf8)) }
    }
}

@MainActor
struct CrossCurrencyTransferTests {
    @Test func debitsAndCreditsRespectiveAmounts() {
        let source = Conto(name: "USD", type: .checking, initialBalance: 500)
        let destination = Conto(name: "EUR", type: .checking, initialBalance: 100)
        let transfer = Transaction(amount: 100, type: .transfer)
        transfer.destinationAmount = 90
        transfer.setFromConto(source)
        transfer.setToConto(destination)
        source.outgoingTransactions = [transfer]
        destination.incomingTransactions = [transfer]
        #expect(source.balance == 400)
        #expect(destination.balance == 190)
        #expect(transfer.displayAmount(for: source.id) == -100)
        #expect(transfer.displayAmount(for: destination.id) == 90)
        let snapshot = TransactionSnapshot(from: transfer)
        #expect(BalanceCalculator.netChange(for: snapshot, contiIDs: [destination.id]) == 90)
        #expect(BalanceCalculator.netChange(for: snapshot, contiIDs: [source.id]) == -100)
    }
}
