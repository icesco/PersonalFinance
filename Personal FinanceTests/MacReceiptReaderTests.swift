#if os(macOS)
import AppKit
import PDFKit
import Testing
import FinanceCore
@testable import Personal_Finance

@MainActor
struct MacReceiptReaderTests {
    private func receiptImage() throws -> NSBitmapImageRep {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1200, pixelsHigh: 500,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 1200, height: 500).fill()
        ("TOTALE EUR 73,25" as NSString).draw(at: NSPoint(x: 40, y: 200), withAttributes: [
            .font: NSFont.systemFont(ofSize: 60), .foregroundColor: NSColor.black
        ])
        return bitmap
    }

    private func pdf(includeScan: Bool) throws -> Data {
        let data = NSMutableData()
        let consumer = try #require(CGDataConsumer(data: data))
        var bounds = CGRect(x: 0, y: 0, width: 1200, height: 700)
        let context = try #require(CGContext(consumer: consumer, mediaBox: &bounds, nil))
        let scannedImage = includeScan ? try receiptImage().cgImage : nil
        context.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        ("Documento di prova" as NSString).draw(at: NSPoint(x: 40, y: 600), withAttributes: [
            .font: NSFont.systemFont(ofSize: 30), .foregroundColor: NSColor.black
        ])
        if let image = scannedImage {
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1200, height: 500))
        } else {
            ("TOTALE EUR 25,90" as NSString).draw(at: NSPoint(x: 40, y: 400), withAttributes: [
                .font: NSFont.systemFont(ofSize: 40), .foregroundColor: NSColor.black
            ])
        }
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    @Test func readsImageOnSamePageAsSelectableHeader() async throws {
        let data = try pdf(includeScan: true)
        let document = try #require(PDFDocument(data: data))
        let selectable = try #require(document.page(at: 0)?.string)
        #expect(selectable.contains("Documento di prova"))
        #expect(!selectable.contains("73,25"))
        let text = try await ReceiptReader.read(data: data, isPDF: true)
        #expect(text.contains("Documento di prova"))
        #expect(ReceiptAmounts.candidates(in: text).contains { $0.amount == Decimal(string: "73.25") && $0.isPossibleTotal })
    }

    @Test func readsImageLocally() async throws {
        let data = try #require(try receiptImage().representation(using: .png, properties: [:]))
        let text = try await ReceiptReader.read(data: data, isPDF: false)
        #expect(ReceiptAmounts.candidates(in: text).contains { $0.amount == Decimal(string: "73.25") && $0.isPossibleTotal })
    }

    @Test func keepsSelectableTotalWithoutDuplicatingOCRCopy() async throws {
        let text = try await ReceiptReader.read(data: pdf(includeScan: false), isPDF: true)
        let candidates = ReceiptAmounts.candidates(in: text)
        #expect(candidates.filter { $0.amount == Decimal(string: "25.90") }.count == 1)
    }
}
#endif
