import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Testing
@testable import FinanceCore

struct WebsiteLogoTests {
    @Test func validatesPublicHTTPSDomainsAndSearchAliases() throws {
        #expect(WebsiteLogoService.siteURL(" example.com/a?q=1 ")?.absoluteString == "https://example.com/")
        #expect(WebsiteLogoService.siteURL("https://www.example.com/") != nil)
        for input in ["http://example.com", "localhost", "127.0.0.1", "https://192.168.1.1", "https://[::1]", "https://user:password@example.com", "bank.local", "https://example.com:8080", "data:image/png;base64,a"] {
            #expect(WebsiteLogoService.siteURL(input) == nil)
        }
        #expect(LogoBrand.matching("amex").first?.name == "American Express")
        #expect(LogoBrand.matching("credit agricole").first?.name == "Crédit Agricole")
    }

    @Test func extractsRankedIconsRegardlessOfAttributeOrderAndRejectsUnsafeURLs() {
        let html = """
        <img alt="Brand logo" src="/brand.png">
        <link HREF='/touch.png?x=1&amp;y=2' sizes="180x180" REL='apple-touch-icon'>
        <link rel=icon href=/favicon.ico>
        <link rel='shortcut icon' href='/favicon.ico'>
        <link rel=icon href='http://example.com/unsafe.png'>
        <link rel=icon href='https://127.0.0.1/private.png'>
        <link rel=icon href='/icon.svg'>
        <link rel=icon href='//cdn.example.com/icon.png'>
        """
        let urls = WebsiteLogoService.imageURLs(html: html, page: URL(string: "https://example.com/home/")!)
        #expect(urls.map(\.absoluteString) == ["https://example.com/touch.png?x=1&y=2", "https://example.com/favicon.ico", "https://cdn.example.com/icon.png", "https://example.com/brand.png"])
    }

    @Test func keepsAnEnclosedWhiteDetailAndRemovesOnlyEdgeBackground() throws {
        let data = try samplePNG()
        let normalized = try AccountLogoImage.normalize(data)
        let cleaned = try AccountLogoImage.removingLightBackground(data)
        let normalPixels = try pixels(normalized)
        let cleanPixels = try pixels(cleaned)
        #expect(normalPixels[3] == 255)
        #expect(cleanPixels[3] == 0)
        #expect(cleanPixels[(2 * 5 + 2) * 4 + 3] == 255)
        #expect(cleanPixels[(2 * 5 + 2) * 4] == 255)
        #expect(cleanPixels[(1 * 5 + 1) * 4 + 3] == 255)
        #expect(cleaned.count <= 128 * 1024)
        #expect(throws: (any Error).self) { try AccountLogoImage.normalize(Data("not an image".utf8)) }
    }

    @Test func fallbackIconsWorkWhenHomePageIsBlocked() async throws {
        let png = try samplePNG()
        let service = WebsiteLogoService { url, _ in
            if url.path == "/" { throw WebsiteLogoService.Failure.invalidResponse }
            return LogoWebResponse(data: png, url: url, contentType: "image/png")
        }
        let logos = try await service.logos(for: "example.com")
        #expect(logos.count == 1) // identical image bytes are deduplicated
        #expect(logos.first?.source.path == "/apple-touch-icon.png")
    }

    @Test func cacheAvoidsRepeatedNetworkRequestsAndCancellationStopsLookup() async throws {
        let png = try samplePNG()
        let counter = LogoRequestCounter()
        let service = WebsiteLogoService { url, _ in
            await counter.increment()
            if url.path == "/" {
                return LogoWebResponse(data: Data("<link rel='icon' href='/logo.png'>".utf8), url: url, contentType: "text/html")
            }
            return LogoWebResponse(data: png, url: url, contentType: "image/png")
        }
        _ = try await service.logos(for: "example.com")
        let firstCount = await counter.count
        _ = try await service.logos(for: "example.com")
        #expect(await counter.count == firstCount)
        let cancelled = WebsiteLogoService { _, _ in throw CancellationError() }
        await #expect(throws: CancellationError.self) { try await cancelled.logos(for: "example.com") }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["FINANCE_LIVE_LOGO_TESTS"] == "1"),
          arguments: ["www.revolut.com", "www.americanexpress.com", "www.credit-agricole.it", "www.intesasanpaolo.com"])
    func liveOfficialSiteLookup(domain: String) async throws {
        let logos = try await WebsiteLogoService().logos(for: domain)
        #expect(!logos.isEmpty)
        #expect(logos.allSatisfy { !$0.data.isEmpty && $0.data.count <= 128 * 1024 })
        print("Logo lookup \(domain): \(logos.count) images")
    }

    private func samplePNG() throws -> Data {
        var bytes = [UInt8](repeating: 255, count: 5 * 5 * 4)
        for y in 1...3 {
            for x in 1...3 where x != 2 || y != 2 {
                for channel in 0..<3 { bytes[(y * 5 + x) * 4 + channel] = 0 }
            }
        }
        let image = try #require(bytes.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: 5, height: 5, bitsPerComponent: 8, bytesPerRow: 20,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)?.makeImage()
        })
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func pixels(_ data: Data) throws -> [UInt8] {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }
}

private actor LogoRequestCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}
