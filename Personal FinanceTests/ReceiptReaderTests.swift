import Foundation
import Testing
import FinanceCore
@testable import Personal_Finance
#if os(iOS)
import UIKit
import PDFKit

@MainActor
struct ReceiptReaderTests {
    @Test(arguments: [false, true])
    func readsScannedPageAlongsideSelectableText(samePage: Bool) async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1000, height: 400)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1000, height: 400))
            ("TOTALE EUR 73,25" as NSString).draw(at: CGPoint(x: 40, y: 100), withAttributes: [
                .font: UIFont.systemFont(ofSize: 60), .foregroundColor: UIColor.black
            ])
        }
        let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 1000, height: 400)).pdfData { context in
            context.beginPage()
            ("Documento di prova" as NSString).draw(at: CGPoint(x: 40, y: 40), withAttributes: [.font: UIFont.systemFont(ofSize: 24)])
            if !samePage { context.beginPage() }
            image.draw(in: samePage
                ? CGRect(x: 0, y: 100, width: 750, height: 300)
                : CGRect(x: 0, y: 0, width: 1000, height: 400))
        }
        let document = try #require(PDFDocument(data: data))
        let scannedText = (document.page(at: samePage ? 0 : 1)?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(!scannedText.contains("73,25"))
        #expect(samePage ? scannedText.contains("Documento di prova") : scannedText.isEmpty)
        let text = try await ReceiptReader.read(data: data, isPDF: true)
        #expect(text.contains("Documento di prova"))
        #expect(ReceiptAmounts.candidates(in: text).contains { $0.amount == Decimal(string: "73.25") && $0.isPossibleTotal })
    }

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
