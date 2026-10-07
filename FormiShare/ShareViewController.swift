import UIKit
import UniformTypeIdentifiers
import SwiftUI
import FinanceCore
import PDFKit
import ImageIO

final class ShareViewController: UIViewController {
    private var hosting: UIHostingController<ShareCaptureView>?
    private var preparedCaptures: [PendingCapture]?
    override func viewDidLoad() {
        super.viewDidLoad()
        let content = ShareCaptureView(onSave: { [weak self] in try await self?.save() }, onCancel: { [weak self] in
            self?.extensionContext?.cancelRequest(withError: NSError(domain: "FormiShare", code: NSUserCancelledError))
        })
        let host = UIHostingController(rootView: content)
        addChild(host); view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor), host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor), host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self); hosting = host
    }
    @MainActor private func save() async throws {
        if let preparedCaptures {
            for capture in preparedCaptures { try CaptureStore.enqueue(capture) }
            extensionContext?.completeRequest(returningItems: nil)
            return
        }
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { throw CaptureStore.Failure.empty }
        var captures: [PendingCapture] = []
        var texts: [String] = []
        for item in items {
            if let text = item.attributedContentText?.string, !text.isEmpty { texts.append(text) }
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) || provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    guard captures.count < 5 else { throw ShareFailure.tooMany }
                    let type = provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) ? UTType.pdf.identifier :
                        (provider.registeredTypeIdentifiers.first { UTType($0)?.conforms(to: .image) == true } ?? UTType.image.identifier)
                    let file = try await readFile(provider, type: type)
                    captures.append(PendingCapture(source: "share", sourceName: "Documento condiviso", text: "",
                        filename: provider.suggestedName ?? file.1, contentType: type, document: file.0))
                } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    guard captures.count < 5 else { throw ShareFailure.tooMany }
                    let file = try await readFileURL(provider)
                    let type: String
                    if PDFDocument(data: file.0) != nil { type = UTType.pdf.identifier }
                    else if let image = CGImageSourceCreateWithData(file.0 as CFData, nil),
                            CGImageSourceGetCount(image) > 0, let imageType = CGImageSourceGetType(image) { type = imageType as String }
                    else { throw ShareFailure.unsupportedFile }
                    captures.append(PendingCapture(source: "share", sourceName: "Documento condiviso", text: "",
                        filename: provider.suggestedName ?? file.1, contentType: type, document: file.0))
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    let text = try await readText(provider)
                    if !text.isEmpty { texts.append(text) }
                }
            }
        }
        var seen = Set<String>()
        let text = texts.filter { seen.insert($0).inserted }.joined(separator: "\n")
        guard text.count <= 30_000 else { throw CaptureStore.Failure.tooLarge }
        if captures.isEmpty { captures = [PendingCapture(source: "share", sourceName: "Testo condiviso", text: text)] }
        else { for capture in captures { capture.originalText = text } }
        // Keep IDs stable if a later write fails and the user retries.
        preparedCaptures = captures
        for capture in captures { try CaptureStore.enqueue(capture) }
        extensionContext?.completeRequest(returningItems: nil)
    }
    private func readFile(_ provider: NSItemProvider, type: String) async throws -> (Data, String) {
        let fallbackName = provider.suggestedName ?? "Documento condiviso"
        do {
            return try await readFileRepresentation(provider, type: type)
        } catch {
            return try await withCheckedThrowingContinuation { continuation in
                provider.loadDataRepresentation(forTypeIdentifier: type) { data, error in
                    if let error { continuation.resume(throwing: error); return }
                    guard let data, !data.isEmpty else { continuation.resume(throwing: CaptureStore.Failure.empty); return }
                    guard data.count <= 10 * 1024 * 1024 else { continuation.resume(throwing: CaptureStore.Failure.tooLarge); return }
                    continuation.resume(returning: (data, fallbackName))
                }
            }
        }
    }
    private func readFileRepresentation(_ provider: NSItemProvider, type: String) async throws -> (Data, String) {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                do {
                    if let error { throw error }
                    guard let url else { throw CaptureStore.Failure.empty }
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size > 0, size <= 10 * 1024 * 1024 else { throw CaptureStore.Failure.tooLarge }
                    // Copy within the provider callback: its temporary URL expires afterwards.
                    continuation.resume(returning: (try Data(contentsOf: url), url.lastPathComponent))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
    private func readFileURL(_ provider: NSItemProvider) async throws -> (Data, String) {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                do {
                    if let error { throw error }
                    let url: URL?
                    if let value = item as? URL { url = value }
                    else if let data = item as? Data, let value = String(data: data, encoding: .utf8) { url = URL(string: value) }
                    else { url = nil }
                    guard let url, url.isFileURL else { throw ShareFailure.unsupportedFile }
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size > 0, size <= 10 * 1024 * 1024 else { throw CaptureStore.Failure.tooLarge }
                    continuation.resume(returning: (try Data(contentsOf: url), url.lastPathComponent))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
    private func readText(_ provider: NSItemProvider) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, error in
                if let error { continuation.resume(throwing: error); return }
                if let text = item as? String { continuation.resume(returning: text) }
                else if let data = item as? Data, let text = String(data: data, encoding: .utf8) { continuation.resume(returning: text) }
                else if let url = item as? URL {
                    do {
                        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                        guard size <= 120_000 else { throw CaptureStore.Failure.tooLarge }
                        continuation.resume(returning: try String(contentsOf: url, encoding: .utf8))
                    } catch { continuation.resume(throwing: error) }
                } else { continuation.resume(throwing: CaptureStore.Failure.empty) }
            }
        }
    }
}

private enum ShareFailure: LocalizedError {
    case tooMany, unsupportedFile
    var errorDescription: String? {
        switch self {
        case .tooMany: "Condividi al massimo 5 documenti alla volta."
        case .unsupportedFile: "Condividi un PDF o un’immagine. Questo file non è supportato."
        }
    }
}
private struct ShareCaptureView: View {
    var onSave: () async throws -> Void
    var onCancel: () -> Void
    @State private var saving = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "tray.and.arrow.down").font(.system(size: 44)).foregroundStyle(.tint)
                Text("Aggiungi a Da approvare").font(.title2.bold())
                Text("Conserva documenti e testo in Formi. Potrai controllare i dati e scegliere il conto prima di registrare il movimento.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                Text("Nessun saldo o budget verrà modificato.").font(.footnote)
                if let error { Text(error).foregroundStyle(.red) }
                Button(saving ? "Acquisizione…" : "Aggiungi a Formi") {
                    saving = true
                    Task { do { try await onSave() } catch { self.error = error.localizedDescription; saving = false } }
                }.buttonStyle(.borderedProminent).disabled(saving)
            }.padding(28)
            .navigationTitle("Formi").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annulla", action: onCancel).disabled(saving) } }
        }
    }
}
