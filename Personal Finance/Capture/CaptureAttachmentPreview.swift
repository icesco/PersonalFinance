import SwiftUI
import PDFKit
import ImageIO
import UniformTypeIdentifiers
import FinanceCore

/// Bounded previews are independent of OCR and cached only in memory.
private actor CaptureThumbnailRenderer {
    static let shared = CaptureThumbnailRenderer()
    private let cache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.countLimit = 40
        cache.totalCostLimit = 24 * 1024 * 1024
        return cache
    }()
    func thumbnail(id: UUID, data: Data, isPDF: Bool, pixels: Int) async -> Data? {
        let key = "\(id)-\(pixels)" as NSString
        if let cached = cache.object(forKey: key) { return cached as Data }
        let result = await Task.detached(priority: .utility) {
            let image: CGImage?
            if isPDF {
                guard let page = PDFDocument(data: data)?.page(at: 0) else { return nil as Data? }
                let bounds = page.bounds(for: .mediaBox)
                guard bounds.width > 0, bounds.height > 0, bounds.width.isFinite, bounds.height.isFinite else { return nil }
                let scale = CGFloat(pixels) / max(bounds.width, bounds.height)
                let preview = page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
                #if os(iOS)
                image = preview.cgImage
                #else
                image = preview.cgImage(forProposedRect: nil, context: nil, hints: nil)
                #endif
            } else {
                guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
                image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: pixels
                ] as CFDictionary)
            }
            guard let image else { return nil }
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { return nil }
            return output as Data
        }.value
        if let result { cache.setObject(result as NSData, forKey: key, cost: result.count) }
        return result
    }
}

struct CaptureAttachmentPreview: View {
    let capture: PendingCapture
    var compact = false
    @State private var thumbnail: Image?
    private var isPDF: Bool { capture.contentType == UTType.pdf.identifier }
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.white
            if let thumbnail {
                thumbnail.resizable().scaledToFit().padding(compact ? 3 : 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Image(systemName: isPDF ? "doc.richtext" : "photo")
                    .font(compact ? .title2 : .largeTitle)
                    .foregroundStyle(ForgiaPalette.mutedText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Text(isPDF ? "PDF" : "Foto")
                .font(.system(size: compact ? 9 : 11, weight: .semibold))
                .foregroundStyle(ForgiaPalette.accent)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(ForgiaPalette.sageSurface, in: Capsule())
                .padding(6)
        }
        .frame(width: compact ? 64 : nil, height: compact ? 84 : 220)
        .clipShape(RoundedRectangle(cornerRadius: compact ? 10 : 14))
        .overlay(RoundedRectangle(cornerRadius: compact ? 10 : 14).stroke(ForgiaPalette.border, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isPDF ? "Anteprima della prima pagina del PDF" : "Anteprima della foto")
        .task(id: capture.id) {
            guard let data = capture.document else { return }
            guard let rendered = await CaptureThumbnailRenderer.shared.thumbnail(id: capture.id, data: data, isPDF: isPDF, pixels: compact ? 240 : 900) else { return }
            guard !Task.isCancelled else { return }
            #if os(iOS)
            if let image = UIImage(data: rendered) { thumbnail = Image(uiImage: image) }
            #else
            if let image = NSImage(data: rendered) { thumbnail = Image(nsImage: image) }
            #endif
        }
    }
}
