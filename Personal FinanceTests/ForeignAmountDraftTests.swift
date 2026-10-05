import Foundation
import SwiftData
import Testing
import FinanceCore
@testable import Personal_Finance

@MainActor
struct ForeignAmountDraftTests {
    private var savedConversion: ForeignAmountDraft {
        ForeignAmountDraft(originalAmount: 100, originalCurrency: "USD", targetCurrency: "EUR",
                           rate: Decimal(string: "0.9")!, rateDay: "2026-10-02", source: "BCE")
    }

    @Test func reopeningPreservesAmountRateAndProvenance() {
        let editor = ForeignAmountEditor(targetCurrency: "EUR", existing: savedConversion)
        #expect(editor.draft == savedConversion)
    }

    @Test func changingAmountKeepsRateSourceButChangingRateUsesManualSource() throws {
        var editor = ForeignAmountEditor(targetCurrency: "EUR", existing: savedConversion)
        editor.originalAmount = "125,50"
        #expect(editor.draft?.source == "BCE")
        #expect(editor.draft?.rateDay == "2026-10-02")
        #expect(editor.draft?.converted == Decimal(string: "112.95"))
        editor.rateText = "0,8"
        #expect(editor.draft?.source == "Manuale")
        #expect(editor.draft?.rateDay == nil)
        #expect(editor.draft?.converted == Decimal(string: "100.40"))
    }

    @Test func changingCurrencyCannotReuseAnotherCurrencySource() throws {
        var editor = ForeignAmountEditor(targetCurrency: "EUR", existing: savedConversion)
        editor.originalCurrency = "GBP"
        #expect(editor.draft?.source == "Manuale")
        editor.clearRate()
        #expect(editor.draft == nil)
        try editor.apply(CurrencyRateSnapshot(day: "2026-10-05", perEuro: ["GBP": Decimal(string: "0.8")!]))
        #expect(editor.draft?.rate == Decimal(string: "1.25"))
        #expect(editor.draft?.rateDay == "2026-10-05")
        #expect(editor.draft?.source == "BCE")
    }

    @Test func changingDestinationRejectsOldConversion() {
        let editor = ForeignAmountEditor(targetCurrency: "USD", existing: savedConversion)
        #expect(editor.originalCurrency != "USD")
        #expect(editor.originalAmount.isEmpty)
        #expect(editor.draft == nil)
    }

    @Test func freezesOriginalAndAppliedRateInStore() throws {
        let container = try FinanceCoreModule.createModelContainer(inMemory: true)
        let value = ForeignAmountDraft(originalAmount: 100, originalCurrency: "USD", targetCurrency: "EUR", rate: Decimal(string: "0.9")!, rateDay: "2026-10-02", source: "BCE")
        let transaction = FinanceTransaction(amount: try #require(value.converted), type: .expense)
        value.apply(to: transaction)
        container.mainContext.insert(transaction)
        try container.mainContext.save()
        let reader = ModelContext(container)
        let stored = try #require(reader.fetch(FetchDescriptor<FinanceTransaction>()).first)
        #expect(stored.amount == 90)
        #expect(stored.originalAmount == 100)
        #expect(stored.originalCurrency == "USD")
        #expect(stored.exchangeRateDate == "2026-10-02")
        #expect(ForeignAmountDraft.load(stored) == value)
        ForeignAmountDraft.clear(stored)
        #expect(stored.amount == 90)
        #expect(stored.originalAmount == nil && stored.exchangeRate == nil)
    }
}
