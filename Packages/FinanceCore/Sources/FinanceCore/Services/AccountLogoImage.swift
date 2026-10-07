import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

/// Portable PNGs, small enough for account storage and shared-book records.
public enum AccountLogoImage {
    public enum Failure: Error { case invalid }

    public static func normalize(_ data: Data) throws -> Data {
        guard data.count <= 10 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 176,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw Failure.invalid }
        return try png(image)
    }

    /// Removes only near-white pixels connected to the image edges, preserving enclosed white details.
    /// Always opt-in: white can be part of a brand's design.
    public static func removingLightBackground(_ data: Data) throws -> Data {
        let normalized = try normalize(data)
        guard let source = CGImageSourceCreateWithData(normalized as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw Failure.invalid }
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let output: CGImage? = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return nil }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            guard let bytes = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return nil }
            var visited = [Bool](repeating: false, count: width * height)
            var queue: [Int] = []
            func enqueue(_ index: Int) {
                guard !visited[index] else { return }
                visited[index] = true
                let offset = index * 4
                let alpha = Int(bytes[offset + 3])
                let nearWhite = alpha > 0 && (0..<3).allSatisfy { Int(bytes[offset + $0]) * 255 >= alpha * 240 }
                if alpha == 0 || nearWhite { queue.append(index) }
            }
            for x in 0..<width { enqueue(x); enqueue((height - 1) * width + x) }
            for y in 0..<height { enqueue(y * width); enqueue(y * width + width - 1) }
            var cursor = 0
            while cursor < queue.count {
                let index = queue[cursor]; cursor += 1
                for channel in 0..<4 { bytes[index * 4 + channel] = 0 }
                let x = index % width, y = index / width
                if x > 0 { enqueue(index - 1) }
                if x + 1 < width { enqueue(index + 1) }
                if y > 0 { enqueue(index - width) }
                if y + 1 < height { enqueue(index + width) }
            }
            return context.makeImage()
        }
        guard let output else { throw Failure.invalid }
        return try png(output)
    }

    private static func png(_ image: CGImage) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { throw Failure.invalid }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination), output.length <= 128 * 1024 else { throw Failure.invalid }
        return output as Data
    }
}
