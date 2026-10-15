import Foundation
import SwiftData
import Testing
@testable import FinanceCore

struct MonthlyFundingSplitTests {
    private func decimal(_ value: String) -> Decimal { Decimal(string: value)! }

    @Test func equalAndCustomSharesAlwaysCompleteTheShortfall() throws {
        let equal = try #require(MonthlyFundingSplit(shortfall: decimal("522.60"), currency: "EUR"))
        #expect(equal.firstAmount == decimal("261.30"))
        #expect(equal.secondAmount == decimal("261.30"))
        let custom = try #require(MonthlyFundingSplit(shortfall: decimal("522.60"), firstPercentage: 60, currency: "EUR"))
        #expect(custom.firstAmount == decimal("313.56"))
        #expect(custom.secondAmount == decimal("209.04"))
        #expect(custom.secondPercentage == 40)
    }

    @Test func indivisibleCentsAndCurrencyPrecisionDoNotLoseOrInventMoney() throws {
        for (amount, currency) in [("100.01", "EUR"), ("101", "JPY"), ("1.005", "KWD")] {
            let total = decimal(amount)
            for percentage in [Decimal(0), decimal("33.333"), 50, 100] {
                let split = try #require(MonthlyFundingSplit(shortfall: total, firstPercentage: percentage, currency: currency))
                #expect(split.firstAmount + split.secondAmount == total)
                #expect(split.firstAmount >= 0 && split.secondAmount >= 0)
            }
        }
        let odd = try #require(MonthlyFundingSplit(shortfall: decimal("100.01"), currency: "EUR"))
        #expect(odd.firstAmount == 50)
        #expect(odd.secondAmount == decimal("50.01"))
        #expect(MonthlyFundingSplit(shortfall: 101, currency: "JPY")?.firstAmount == 50)
        #expect(MonthlyFundingSplit(shortfall: decimal("1.005"), currency: "KWD")?.firstAmount == decimal("0.502"))
    }

    @Test func invalidOrUnknownFundingDoesNotBecomeAZeroContribution() {
        #expect(MonthlyFundingSplit(shortfall: -1, currency: "EUR") == nil)
        #expect(MonthlyFundingSplit(shortfall: .nan, currency: "EUR") == nil)
        #expect(MonthlyFundingSplit(shortfall: 10, firstPercentage: .nan, currency: "EUR") == nil)
        #expect(MonthlyFundingSplit(shortfall: 10, firstPercentage: -1, currency: "EUR") == nil)
        #expect(MonthlyFundingSplit(shortfall: 10, firstPercentage: 101, currency: "EUR") == nil)
        #expect(MonthlyFundingSplit(shortfall: 0, currency: "EUR")?.firstAmount == 0)
    }

    @MainActor @Test func forecastEligibilityIsLimitedToActiveCheckingAccounts() {
        for type in ContoType.allCases {
            let conto = Conto(name: "Conto", type: type)
            #expect(conto.supportsMonthlyForecast == (type == .checking))
            conto.isActive = false
            #expect(!conto.supportsMonthlyForecast)
        }
        let unknown = Conto(name: "Sconosciuto", type: .checking)
        unknown.type = nil
        #expect(!unknown.supportsMonthlyForecast)
    }

    @MainActor @Test func sharedParticipantsRespectAccountAndBookScope() throws {
        let book = Account(name: "Libro")
        let conto = Conto(name: "Comune", type: .checking)
        conto.account = book
        let anna = TransactionPerson(id: "anna", name: "Anna")
        let marco = TransactionPerson(id: "marco", name: "Marco")
        func membership(_ people: [TransactionPerson], contoID: UUID?, bookID: UUID) throws -> SharedBookMembership {
            let row = SharedBookMembership(scopeKey: UUID().uuidString, ownerName: "owner", remoteBookID: UUID(), localBookID: bookID)
            row.localContoID = contoID
            row.peopleJSON = String(data: try JSONEncoder().encode(people), encoding: .utf8)
            return row
        }
        let shared = try membership([marco, anna, anna], contoID: conto.id, bookID: book.id)
        let wholeBook = try membership([TransactionPerson(id: "other", name: "Altra persona")], contoID: nil, bookID: book.id)
        let unrelated = try membership([TransactionPerson(id: "stranger", name: "Estraneo")], contoID: UUID(), bookID: book.id)
        let otherBook = try membership([TransactionPerson(id: "wrong", name: "Altro libro")], contoID: conto.id, bookID: UUID())
        #expect(MonthlyForecastParticipants.people(conto: conto, memberships: [shared, wholeBook, unrelated, otherBook]) == [anna, marco])
        #expect(MonthlyForecastParticipants.people(conto: conto, memberships: [wholeBook, unrelated]) == [TransactionPerson(id: "other", name: "Altra persona")])
        #expect(MonthlyForecastParticipants.people(conto: conto, memberships: [unrelated, otherBook]).isEmpty)
        shared.peopleJSON = "not-json"
        #expect(MonthlyForecastParticipants.people(conto: conto, memberships: [shared, wholeBook]).isEmpty)
        shared.peopleJSON = String(repeating: " ", count: 65_537)
        #expect(MonthlyForecastParticipants.people(conto: conto, memberships: [shared]).isEmpty)
    }
}
