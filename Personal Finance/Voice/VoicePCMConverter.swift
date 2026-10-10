import Foundation
@preconcurrency import AVFoundation

enum VoiceAudioConversionError: LocalizedError {
    case unsupportedFormat
    var errorDescription: String? { "Il formato audio del microfono non è supportato." }
}

// The converter belongs to a single audio tap; AVAudioEngine serializes its callbacks.
final class VoicePCMConverter: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let format: AVAudioFormat

    init(from source: AVAudioFormat, to target: AVAudioFormat) throws {
        guard let converter = AVAudioConverter(from: source, to: target) else {
            throw VoiceAudioConversionError.unsupportedFormat
        }
        self.converter = converter
        format = target
    }

    func convert(_ source: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer? {
        let capacity = AVAudioFrameCount(ceil(Double(source.frameLength) * format.sampleRate / source.format.sampleRate) + 32)
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw VoiceAudioConversionError.unsupportedFormat
        }
        var supplied = false
        var failure: NSError?
        let status = converter.convert(to: output, error: &failure) { _, inputStatus in
            if supplied { inputStatus.pointee = .noDataNow; return nil }
            supplied = true
            inputStatus.pointee = .haveData
            return source
        }
        if let failure { throw failure }
        guard status != .error else { throw VoiceAudioConversionError.unsupportedFormat }
        return output.frameLength > 0 ? output : nil
    }
}
