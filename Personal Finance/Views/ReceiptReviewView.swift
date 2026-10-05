import SwiftUI
import Vision
import PDFKit
import ImageIO
import FinanceCore

/// Vision recognition runs locally and never sends receipt data to a server.
enum ReceiptReader {
    enum Failure: LocalizedError {
        case unreadable, scannedPDF
        var errorDescription: String? {
            switch self {
            case .unreadable: "Non è stato riconosciuto testo leggibile. Prova una foto più nitida."
            case .scannedPDF: "Questo PDF non contiene testo selezionabile. Per leggerlo, importa una foto dello scontrino."
            }
        }
    }
    static func read(data: Data, isPDF: Bool) async throws -> String {
        let work = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            if isPDF {
                guard let document = PDFDocument(data: data) else { throw Failure.unreadable }
                let text = (0..<min(document.pageCount, 5)).compactMap { document.page(at: $0)?.string }.joined(separator: "\n")
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.scannedPDF }
                return text
            }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["it-IT", "en-US"]
            request.usesLanguageCorrection = false
            var orientation = CGImagePropertyOrientation.up
            if let source = CGImageSourceCreateWithData(data as CFData, nil),
               let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
               let value = properties[kCGImagePropertyOrientation] as? UInt32 {
                orientation = CGImagePropertyOrientation(rawValue: value) ?? .up
            }
            try VNImageRequestHandler(data: data, orientation: orientation).perform([request])
            try Task.checkCancellation()
            let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            guard !text.isEmpty else { throw Failure.unreadable }
            return text
        }
        return try await withTaskCancellationHandler {
            let result = try await work.value
            try Task.checkCancellation()
            return result
        } onCancel: { work.cancel() }
    }
}

struct ReceiptReviewView: View {
    let attachment: AttachmentDraft
    var onSelectAmount: ((Decimal) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var text: String?
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Lettura eseguita sul dispositivo. Controlla lo scontrino: gli importi riconosciuti possono includere subtotali, IVA e resto.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if let text {
                    let candidates = ReceiptAmounts.candidates(in: text)
                    Section("Importi da verificare") {
                        if candidates.isEmpty { Text("Nessun importo riconosciuto. Puoi inserirlo manualmente nel movimento.") }
                        ForEach(candidates) { candidate in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(candidate.line).font(.subheadline)
                                if candidate.isPossibleTotal { Text("Possibile totale").font(.caption).foregroundStyle(.secondary) }
                                if let onSelectAmount {
                                    Button("Usa \(candidate.amount.formatted(.number.precision(.fractionLength(2))))") {
                                        onSelectAmount(candidate.amount)
                                        dismiss()
                                    }.buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                    Section("Testo riconosciuto") { Text(text).textSelection(.enabled) }
                    if attachment.contentType == "com.adobe.pdf" {
                        Text("Lettura delle prime cinque pagine del PDF.").font(.caption).foregroundStyle(.secondary)
                    }
                } else if let error {
                    Text(error)
                } else {
                    ProgressView("Lettura scontrino…")
                }
            }
            .navigationTitle("Leggi scontrino")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() } }
            }
            .task(id: attachment.id) {
                do { text = try await ReceiptReader.read(data: attachment.data, isPDF: attachment.contentType == "com.adobe.pdf") }
                catch is CancellationError { }
                catch { self.error = error.localizedDescription }
            }
        }
    }
}
