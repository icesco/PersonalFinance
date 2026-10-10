import Foundation
import AVFoundation
import Speech

@main struct RecorderChecks {
    static func main() async throws {
        var checks = 0
        func check(_ condition: Bool, _ name: String) throws {
            guard condition else { throw NSError(domain: "RecorderChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: name]) }
            checks += 1
        }
        func candidates(_ preferred: [String], _ current: String, _ supported: [String]) -> [String] {
            VoiceRecognitionLocale.candidates(preferredLanguages: preferred, current: Locale(identifier: current),
                supported: Set(supported.map { Locale(identifier: $0) })).map(\.identifier)
        }
        try check(candidates(["it-IT"], "en_US", ["it_IT", "en_US"]) == ["it_IT"], "App language takes precedence over regional locale")
        try check(candidates(["it-CH"], "it_CH", ["it_IT", "en_US"]) == ["it_IT"], "Italian variant resolves to available Italian model")
        try check(candidates(["it-IT", "en-US"], "en_US", ["en_US"]).isEmpty, "Unsupported language never silently becomes English")
        try check(candidates(["en-GB"], "en_US", ["en_US", "en_GB"]).first == "en_GB", "Exact preferred variant comes first")
        try check(candidates([], "it_IT", ["it_IT", "en_US"]) == ["it_IT"], "Missing preferences use current locale")

        let sourceFormat = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        let targetFormat = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let converter = try VoicePCMConverter(from: sourceFormat, to: targetFormat)
        let source = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: 2048)!
        source.frameLength = 2048
        for channel in 0..<2 {
            for frame in 0..<2048 {
                source.floatChannelData![channel][frame] = Float(sin(Double(frame) * 2 * .pi * 440 / 48_000)) * 0.2
            }
        }
        let output = try converter.convert(source)!
        try check(output.format.sampleRate == 16_000 && output.format.channelCount == 1, "Hardware audio is resampled and downmixed")
        try check(output.frameLength > 500 && output.frameLength <= 700, "Converted frame count matches sample-rate ratio")
        try check((0..<Int(output.frameLength)).contains { abs(output.floatChannelData![0][$0]) > 0.01 }, "Conversion preserves audio signal")
        let retainedSample = output.floatChannelData![0][100]
        for frame in 0..<2048 { source.floatChannelData![0][frame] = 0; source.floatChannelData![1][frame] = 0 }
        _ = try converter.convert(source)
        try check(output.floatChannelData![0][100] == retainedSample, "Queued analyzer buffers do not alias reused microphone buffers")
        let locales = await SpeechTranscriber.supportedLocales
        print("SpeechTranscriber on this Mac: available=\(SpeechTranscriber.isAvailable), Italian=\(locales.contains { $0.language.languageCode?.identifier == "it" })")
        print("Recorder: \(checks)/\(checks) checks passed")
    }
}
