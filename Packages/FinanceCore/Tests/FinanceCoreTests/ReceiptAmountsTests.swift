import Foundation
import Testing
@testable import FinanceCore

struct ReceiptAmountsTests {
    @Test func findsTotalsWithoutConfusingDatesAndTax() {
        let values = ReceiptAmounts.candidates(in: "04.10.2026\nPasta 2,50\nTOTALE IVA 0,50\nTOTALE EUR 12,34\nRESTO 7,66")
        #expect(values.count == 4)
        #expect(values.first?.amount == Decimal(string: "12.34"))
        #expect(values.filter(\.isPossibleTotal).count == 1)
    }
    @Test func supportsBothDecimalConventionsAndGrouping() {
        let values = ReceiptAmounts.candidates(in: "TOTAL 1,234.56\nTOTALE 1.234,56\nImporto 1 234,56\nCodice 123456\n0,00\nSconto - 5,00\nIVA 22,00%")
        #expect(values.count == 3)
        #expect(values.allSatisfy { $0.amount == Decimal(string: "1234.56") })
    }
}
