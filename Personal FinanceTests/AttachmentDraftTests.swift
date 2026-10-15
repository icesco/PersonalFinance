import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Testing
@testable import Personal_Finance

struct AttachmentDraftTests {
    @Test func thumbnailBoundsLargeImageAndKeepsOriginalData() async throws {
        let context = try #require(CGContext(data: nil, width: 4032, height: 3024, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.7, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 4032, height: 3024))
        let original = try #require(context.makeImage())
        let encoded = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(encoded, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, original, nil)
        #expect(CGImageDestinationFinalize(destination))
        let draft = try AttachmentDraft(filename: "large.png", data: encoded as Data)
        let rendered = try #require(await CaptureThumbnailRenderer.shared.thumbnail(id: draft.id,
            data: draft.data, isPDF: false, pixels: 256))
        let source = try #require(CGImageSourceCreateWithData(rendered as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 256)
        #expect(image.height == 192)
        #expect(draft.data == encoded as Data)
        #expect(await CaptureThumbnailRenderer.shared.thumbnail(id: draft.id, data: draft.data,
            isPDF: false, pixels: 256) == rendered)
    }

    @Test func validatesContentAndSizeBeforePersistence() throws {
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=")!
        let draft = try AttachmentDraft(filename: "scontrino.png", data: png)
        #expect(draft.contentType == "public.png")
        #expect(draft.data == png)
        #expect(throws: (any Error).self) { try AttachmentDraft(filename: "vuoto.png", data: Data()) }
        #expect(throws: (any Error).self) { try AttachmentDraft(filename: "falso.jpg", data: Data("non immagine".utf8)) }
        #expect(throws: (any Error).self) { try AttachmentDraft(filename: "grande.pdf", data: Data(repeating: 0, count: 10 * 1024 * 1024 + 1)) }
    }
}
