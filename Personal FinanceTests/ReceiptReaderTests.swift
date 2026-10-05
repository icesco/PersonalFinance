import Foundation
import Testing
import FinanceCore
@testable import Personal_Finance
#if os(iOS)
import UIKit

@MainActor
struct ReceiptReaderTests {
    @Test func readsReceiptImageLocally() async throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 500))
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1200, height: 500))
            let text = "NEGOZIO TEST\nTOTALE EUR 42,50"
            (text as NSString).draw(in: CGRect(x: 50, y: 50, width: 1100, height: 400), withAttributes: [
                .font: UIFont.systemFont(ofSize: 58), .foregroundColor: UIColor.black
            ])
        }
        let data = try #require(image.pngData())
        let text = try await ReceiptReader.read(data: data, isPDF: false)
        #expect(ReceiptAmounts.candidates(in: text).contains { $0.amount == Decimal(string: "42.50") && $0.isPossibleTotal })
    }

    @Test func readsSelectablePDFText() async throws {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 500, height: 500))
        let data = renderer.pdfData { context in
            context.beginPage()
            ("TOTALE 25,90" as NSString).draw(at: CGPoint(x: 40, y: 40), withAttributes: [.font: UIFont.systemFont(ofSize: 24)])
        }
        let text = try await ReceiptReader.read(data: data, isPDF: true)
        #expect(ReceiptAmounts.candidates(in: text).first?.amount == Decimal(string: "25.90"))
    }
}
#endif
