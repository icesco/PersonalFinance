import Foundation
import Testing
@testable import Personal_Finance

@MainActor
struct TransactionSearchTests {
    @Test func matchesWordsAcrossDescriptionNotesCategoryAndAccount() {
        let fields: [String?] = ["Caffè", "Con Anna", "Bar", "Conto corrente", nil]
        #expect(TransactionSearch.matches(query: "  CAFFE   anna corrente ", fields: fields, amount: 12.5))
        #expect(!TransactionSearch.matches(query: "caffe marco", fields: fields, amount: 12.5))
    }

    @Test func amountSupportsCommaAndPoint() {
        #expect(TransactionSearch.matches(query: "12,50", fields: [], amount: 12.5))
        #expect(TransactionSearch.matches(query: "12.50", fields: [], amount: 12.5))
        #expect(!TransactionSearch.matches(query: "19,5", fields: [], amount: 12.5))
    }

    @Test func emptyWhitespaceDoesNotExcludeTransactions() {
        #expect(TransactionSearch.matches(query: " \n ", fields: [nil], amount: 0))
    }
}
