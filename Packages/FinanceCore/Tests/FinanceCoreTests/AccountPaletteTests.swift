import Foundation
import Testing
@testable import FinanceCore

@MainActor
struct AccountPaletteTests {
    @Test func chartsAndWidgetsRespectAccountColorsAcrossFilteringAndRenames() throws {
        let now = Date()
        let a = Conto(name: "Banca", type: .checking, initialBalance: 100, color: "#123456")
        let b = Conto(name: "Risparmi", type: .savings, initialBalance: 50, color: "#007AFF")
        let c = Conto(name: "Contanti", type: .cash, initialBalance: 10)
        let interval = WidgetBalancePeriod.month.interval(containing: now)
        let all = AccountBalanceSeries.make(conti: [a, b, c], selectedIDs: [a.id, b.id, c.id],
            transactions: [], resolutions: [], interval: interval, now: now)
        #expect(all.first { $0.id == a.id }?.colorHex == "#123456")
        #expect(all.first { $0.id == b.id }?.colorHex == "#007AFF")
        #expect(b.color == "#007AFF")
        let original = try #require(all.first { $0.id == c.id }?.colorHex)
        c.name = "Nuovo nome"
        let filtered = AccountBalanceSeries.make(conti: [c], selectedIDs: [c.id], transactions: [],
            resolutions: [], interval: interval, now: now)
        #expect(filtered.first?.colorHex == original)
        let widget = WidgetBalanceSnapshot.make(period: .month, conti: [a, b, c], transactions: [], resolutions: [], now: now)
        for account in [a, b, c] {
            #expect(widget.series.first { $0.id == account.id }?.colorHex == account.displayColorHex)
        }
    }

    @Test func newAccountsPreferAnUnusedColorAndCustomColorsArePreserved() {
        let first = AccountPalette.suggestedColor(used: [])
        let second = AccountPalette.suggestedColor(used: [first])
        #expect(first != second)
        #expect(AccountPalette.displayColor(stored: "#aabbcc", id: UUID()) == "#aabbcc")
        #expect(AccountPalette.displayColor(stored: "#ff3b30", id: UUID()) == "#ff3b30")
    }
}
