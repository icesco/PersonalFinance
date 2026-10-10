import Foundation
import Observation
@preconcurrency import Speech
@preconcurrency import AVFoundation

@MainActor @Observable final class LocalVoiceRecorder {
    private(set) var transcript = ""
    private(set) var isRecording = false
    private(set) var isFinishing = false
    private(set) var error: String?
    private(set) var preparationMessage: String?
    let meter = VoiceAudioMeter()
    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var recognition: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var hasTap = false
    private var sessionID = UUID()
    private var finishTask: Task<Void, Never>?
    private var analyzer: SpeechAnalyzer?
    private var analyzerInput: AsyncStream<AnalyzerInput>.Continuation?
    private var resultTask: Task<Void, Never>?
    #if os(iOS)
    private var audioSessionActive = false
    #endif

    func start(appendingTo prefix: String = "") async {
        stop()
        let id = sessionID
        error = nil
        preparationMessage = nil
        let microphone = await AVCaptureDevice.requestAccess(for: .audio)
        guard !Task.isCancelled, sessionID == id else { return }
        guard microphone else { error = "Consenti l’accesso al microfono nelle impostazioni oppure scrivi il testo."; return }
        do {
            if try await startAnalyzer(id: id, prefix: prefix) { return }
        } catch {
            guard !Task.isCancelled, sessionID == id else { return }
            stop()
            self.error = "Impossibile preparare la trascrizione locale: \(error.localizedDescription). Riprova con una connessione Internet per scaricare il modello vocale."
            return
        }
        guard !Task.isCancelled, sessionID == id else { return }
        let authorized = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in continuation.resume(returning: status == .authorized) }
        }
        guard !Task.isCancelled, sessionID == id else { return }
        guard authorized else { error = "Consenti il riconoscimento vocale nelle impostazioni oppure scrivi il testo."; return }
        let locales = VoiceRecognitionLocale.candidates(preferredLanguages: Locale.preferredLanguages,
            current: .current, supported: SFSpeechRecognizer.supportedLocales())
        guard !locales.isEmpty else {
            error = "La lingua impostata per Formi non è supportata dalla trascrizione vocale Apple. Puoi scrivere il testo."
            return
        }
        let localRecognizers = locales.compactMap { SFSpeechRecognizer(locale: $0) }
            .filter { $0.supportsOnDeviceRecognition }
        guard !localRecognizers.isEmpty else {
            error = "La trascrizione sul dispositivo non è disponibile per questa lingua. Puoi usare la dettatura della tastiera o scrivere il testo."
            return
        }
        guard let recognizer = localRecognizers.first(where: { $0.isAvailable }) else {
            error = "Il riconoscimento vocale non è disponibile al momento. Riprova oppure scrivi il testo."
            return
        }
        self.recognizer = recognizer
        do {
            #if os(iOS)
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audio.setActive(true, options: .notifyOthersOnDeactivation)
            audioSessionActive = true
            #endif
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = true
            self.request = request
            transcript = prefix
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                stop(); error = "Il microfono non è disponibile."; return
            }
            input.installTap(onBus: 0, bufferSize: 2048, format: format) { @Sendable [weak self] buffer, _ in
                request.append(buffer)
                guard let samples = buffer.floatChannelData?.pointee, buffer.frameLength > 0 else { return }
                var energy = 0.0
                var count = 0
                for index in stride(from: 0, to: Int(buffer.frameLength), by: 16) {
                    let value = Double(samples[index])
                    energy += value * value; count += 1
                }
                let decibels = 20 * log10(max(sqrt(energy / Double(max(count, 1))), 0.00001))
                let level = min(1, max(0, (decibels + 55) / 45))
                Task { @MainActor [weak self] in
                    guard let self, self.sessionID == id, self.isRecording else { return }
                    self.meter.level = self.meter.level * 0.65 + level * 0.35
                }
            }
            hasTap = true
            recognition = recognizer.recognitionTask(with: request) { [weak self] result, failure in
                let text = result?.bestTranscription.formattedString
                let finished = result?.isFinal == true
                let message = failure?.localizedDescription
                Task { @MainActor [weak self] in
                    guard let self, self.sessionID == id else { return }
                    if let text { self.transcript = [prefix, text].filter { !$0.isEmpty }.joined(separator: "\n") }
                    if finished || message != nil {
                        self.stop()
                        if let message { self.error = message }
                    }
                }
            }
            engine.prepare()
            try engine.start()
            isRecording = true
        } catch {
            stop()
            self.error = "Impossibile avviare il microfono: \(error.localizedDescription)"
        }
    }

    private func startAnalyzer(id: UUID, prefix: String) async throws -> Bool {
        guard SpeechTranscriber.isAvailable else { return false }
        let preferred = Locale.preferredLanguages.first.map(Locale.init(identifier:)) ?? .current
        let equivalent = await SpeechTranscriber.supportedLocale(equivalentTo: preferred)
        guard !Task.isCancelled, sessionID == id else { throw CancellationError() }
        let supported = await SpeechTranscriber.supportedLocales
        guard !Task.isCancelled, sessionID == id else { throw CancellationError() }
        let locales = VoiceRecognitionLocale.candidates(preferredLanguages: Locale.preferredLanguages,
            current: .current, supported: Set(supported))
        guard let locale = equivalent ?? locales.first else { return false }
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            preparationMessage = "Scarico il modello vocale…"
            try await installation.downloadAndInstall()
        }
        guard !Task.isCancelled, sessionID == id else { throw CancellationError() }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw VoiceAudioConversionError.unsupportedFormat
        }
        guard !Task.isCancelled, sessionID == id else { throw CancellationError() }
        #if os(iOS)
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audio.setActive(true, options: .notifyOthersOnDeactivation)
        audioSessionActive = true
        #endif
        let input = engine.inputNode
        let sourceFormat = input.outputFormat(forBus: 0)
        guard sourceFormat.sampleRate > 0, sourceFormat.channelCount > 0 else {
            throw VoiceAudioConversionError.unsupportedFormat
        }
        let converter = try VoicePCMConverter(from: sourceFormat, to: format)
        let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        analyzerInput = continuation
        try await analyzer.prepareToAnalyze(in: format)
        guard !Task.isCancelled, sessionID == id else { throw CancellationError() }
        transcript = prefix
        resultTask = Task { [weak self] in
            var committed = ""
            do {
                for try await result in transcriber.results {
                    guard let self, self.sessionID == id, !Task.isCancelled else { return }
                    let phrase = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    let current = [committed, phrase].filter { !$0.isEmpty }.joined(separator: " ")
                    self.transcript = [prefix, current].filter { !$0.isEmpty }.joined(separator: "\n")
                    if result.isFinal { committed = current }
                }
            } catch {
                guard let self, self.sessionID == id, !Task.isCancelled else { return }
                self.stop()
                self.error = "La trascrizione si è interrotta: \(error.localizedDescription)"
            }
        }
        try await analyzer.start(inputSequence: stream)
        guard !Task.isCancelled, sessionID == id else { throw CancellationError() }
        input.installTap(onBus: 0, bufferSize: 2048, format: sourceFormat) { @Sendable [weak self] buffer, _ in
            do {
                if let converted = try converter.convert(buffer) {
                    continuation.yield(AnalyzerInput(buffer: converted))
                }
            } catch {
                let message = error.localizedDescription
                Task { @MainActor [weak self] in
                    guard let self, self.sessionID == id else { return }
                    self.stop(); self.error = "Impossibile leggere l’audio: \(message)"
                }
            }
            guard let samples = buffer.floatChannelData?.pointee, buffer.frameLength > 0 else { return }
            var energy = 0.0
            var count = 0
            for index in stride(from: 0, to: Int(buffer.frameLength), by: 16) {
                let value = Double(samples[index])
                energy += value * value; count += 1
            }
            let decibels = 20 * log10(max(sqrt(energy / Double(max(count, 1))), 0.00001))
            let level = min(1, max(0, (decibels + 55) / 45))
            Task { @MainActor [weak self] in
                guard let self, self.sessionID == id, self.isRecording else { return }
                self.meter.level = self.meter.level * 0.65 + level * 0.35
            }
        }
        hasTap = true
        engine.prepare()
        try engine.start()
        preparationMessage = nil
        isRecording = true
        return true
    }

    private func stopAudio() {
        meter.level = 0
        engine.stop()
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
        #if os(iOS)
        if audioSessionActive {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            audioSessionActive = false
        }
        #endif
    }

    /// Keep the recognition task alive long enough to deliver the final words.
    func finish() {
        guard isRecording else { return }
        stopAudio()
        if let analyzer {
            analyzerInput?.finish()
            analyzerInput = nil
            isRecording = false
            isFinishing = true
            let id = sessionID
            let results = resultTask
            finishTask = Task { [weak self] in
                do {
                    try await analyzer.finalizeAndFinishThroughEndOfInput()
                    await results?.value
                    guard let self, self.sessionID == id, !Task.isCancelled else { return }
                    self.stop()
                } catch {
                    guard let self, self.sessionID == id, !Task.isCancelled else { return }
                    self.stop(); self.error = "Impossibile completare la trascrizione: \(error.localizedDescription)"
                }
            }
            return
        }
        request?.endAudio()
        isRecording = false
        isFinishing = true
        let id = sessionID
        finishTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            guard let self, self.sessionID == id else { return }
            self.stop()
        }
    }

    func stop() {
        sessionID = UUID()
        finishTask?.cancel(); finishTask = nil
        stopAudio()
        analyzerInput?.finish(); analyzerInput = nil
        resultTask?.cancel(); resultTask = nil
        if let analyzer { Task { await analyzer.cancelAndFinishNow() } }
        analyzer = nil
        preparationMessage = nil
        request?.endAudio()
        recognition?.cancel()
        recognition = nil
        recognizer = nil
        request = nil
        isRecording = false
        isFinishing = false
    }
}
