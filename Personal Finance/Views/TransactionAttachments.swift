import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import QuickLook
import ImageIO
import PDFKit
import PhotosUI
import FinanceCore
#if os(iOS)
import VisionKit
#endif

struct AttachmentDraft: Identifiable, Sendable {
    let id: UUID
    let filename: String
    let contentType: String
    let data: Data

    init(id: UUID = UUID(), filename: String, data: Data) throws {
        guard !data.isEmpty, data.count <= 10 * 1024 * 1024 else { throw AttachmentFailure.size }
        let type: String
        if data.starts(with: Data("%PDF-".utf8)), PDFDocument(data: data) != nil { type = UTType.pdf.identifier }
        else if let image = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(image) > 0,
                let imageType = CGImageSourceGetType(image) { type = imageType as String }
        else { throw AttachmentFailure.format }
        self.id = id
        self.filename = filename
        self.contentType = type
        self.data = data
    }

    func model() -> TransactionAttachment {
        TransactionAttachment(id: id, filename: filename, contentType: contentType, data: data)
    }
}

enum AttachmentFailure: LocalizedError {
    case size, format, count
    var errorDescription: String? {
        switch self {
        case .size: "Ogni allegato deve essere non vuoto e non superare 10 MB."
        case .format: "Seleziona un'immagine o un PDF valido."
        case .count: "Puoi aggiungere fino a 5 allegati per movimento."
        }
    }
}

struct DraftAttachmentsView: View {
    @Binding var attachments: [AttachmentDraft]
    var onSelectAmount: ((Decimal) -> Void)? = nil
    @State private var reading: AttachmentDraft?
    @State private var importing = false
    @State private var scanning = false
    @State private var selectedPhoto: PhotosPickerItem?
    @Binding var loading: Bool
    /// Thumbnails and action tiles for the card-style forms; off inside system `Form`s.
    var cardStyle = false
    @State private var error: String?

    private var isFull: Bool { attachments.count >= 5 }

    var body: some View {
        Group {
            if cardStyle { card } else { classic }
        }
        #if os(iOS)
        .sheet(isPresented: $scanning) {
            ReceiptCameraCapture(maximumPages: 5 - attachments.count, onComplete: { result in
                scanning = false
                switch result {
                case .success(let scanned): attachments.append(contentsOf: scanned)
                case .failure(let error): self.error = error.localizedDescription
                }
            }, onCancel: { scanning = false })
        }
        #endif
        .modifier(AttachmentImportModifiers(attachments: $attachments, reading: $reading, importing: $importing,
                                            selectedPhoto: $selectedPhoto, loading: $loading, error: $error,
                                            onSelectAmount: onSelectAmount))
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Allegati e scontrini")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ForgiaPalette.mutedText)
                Spacer()
                if !attachments.isEmpty {
                    Text("\(attachments.count)/5")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(ForgiaPalette.mutedText)
                }
            }
            .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 14) {
                if !attachments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(attachments) { attachment in
                                AttachmentThumbnail(attachment: attachment) {
                                    reading = attachment
                                } onRemove: {
                                    withAnimation(.snappy) { attachments.removeAll { $0.id == attachment.id } }
                                }
                            }
                        }
                        .padding(.top, 8)
                        .padding(.trailing, 8)
                    }
                    .scrollClipDisabled()
                }

                HStack(spacing: 8) {
                    #if os(iOS)
                    if VNDocumentCameraViewController.isSupported {
                        Button { scanning = true } label: {
                            AttachmentSourceTile(title: "Scansiona", symbol: "doc.viewfinder", tint: ForgiaPalette.sageSurface)
                        }
                    }
                    #endif
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        AttachmentSourceTile(title: "Foto", symbol: "photo", tint: ForgiaPalette.apricotSurface)
                    }
                    Button { importing = true } label: {
                        AttachmentSourceTile(title: "File", symbol: "paperclip", tint: ForgiaPalette.canvas)
                    }
                }
                .buttonStyle(.plain)
                .disabled(loading || isFull)
                .opacity(loading || isFull ? 0.5 : 1)

                if loading {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Caricamento allegato…").font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                    }
                }
            }
            .padding(14)
            .background(ForgiaPalette.surface, in: RoundedRectangle(cornerRadius: 25, style: .continuous))

            Text(isFull ? "Hai raggiunto il massimo di 5 allegati." : "Immagini e PDF · massimo 5 file da 10 MB, salvati con il movimento. Tocca uno scontrino per leggerne l'importo.")
                .font(.caption)
                .foregroundStyle(ForgiaPalette.mutedText)
                .padding(.horizontal, 4)
        }
    }

    private var classic: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Allegati e scontrini").font(.headline)
            ForEach(attachments) { attachment in
                HStack {
                    Label(attachment.filename, systemImage: "doc")
                        .lineLimit(2)
                    Spacer()
                    Button { reading = attachment } label: { Image(systemName: "text.viewfinder") }
                        .accessibilityLabel("Leggi scontrino \(attachment.filename)")
                    Button(role: .destructive) { attachments.removeAll { $0.id == attachment.id } } label: {
                        Image(systemName: "trash")
                    }.accessibilityLabel("Rimuovi \(attachment.filename)")
                }
            }
            HStack {
                Button("Da file", systemImage: "paperclip") { importing = true }
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label("Da foto", systemImage: "photo")
                }
            }.buttonStyle(.bordered).disabled(loading || attachments.count >= 5)
            #if os(iOS)
            if VNDocumentCameraViewController.isSupported {
                Button("Scansiona scontrino", systemImage: "doc.viewfinder") { scanning = true }
                    .buttonStyle(.bordered)
                    .disabled(loading || attachments.count >= 5)
            }
            #endif
            if loading { ProgressView("Caricamento allegato…") }
            Text("Immagini e PDF · massimo 5 file da 10 MB. Verranno salvati insieme al movimento.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct TransactionAttachmentsSection: View {
    let transaction: FinanceTransaction
    @State private var editing = false
    @State private var previewURL: URL?
    @State private var temporaryDirectory: URL?
    @State private var error: String?
    var body: some View {
        Section {
            ForEach(transaction.attachments ?? []) { attachment in
                Button { preview(attachment) } label: { Label(attachment.filename, systemImage: "doc") }
            }
            Button("Gestisci allegati", systemImage: "paperclip") { editing = true }
                .tint(ForgiaPalette.accent)
        } header: {
            Text("Allegati e scontrini")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ForgiaPalette.mutedText)
                .textCase(nil)
        }
        .sheet(isPresented: $editing) { SavedAttachmentsEditor(transaction: transaction) }
        .quickLookPreview($previewURL)
        .onDisappear { cleanup() }
        .onChange(of: previewURL) { _, value in if value == nil { cleanup() } }
        .alert("Anteprima non disponibile", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
    private func preview(_ attachment: TransactionAttachment) {
        do {
            guard let data = attachment.data else { throw AttachmentFailure.format }
            cleanup()
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            temporaryDirectory = directory
            let ext = UTType(attachment.contentType)?.preferredFilenameExtension ?? "dat"
            let url = directory.appendingPathComponent("Allegato.\(ext)")
            try data.write(to: url, options: .atomic)
            previewURL = url
        } catch { self.error = error.localizedDescription; cleanup() }
    }
    private func cleanup() {
        if let temporaryDirectory { try? FileManager.default.removeItem(at: temporaryDirectory) }
        temporaryDirectory = nil
    }
}

private struct SavedAttachmentsEditor: View {
    let transaction: FinanceTransaction
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var drafts: [AttachmentDraft] = []
    @State private var error: String?
    @State private var loaded = false
    @State private var loadingAttachment = false

    var body: some View {
        NavigationStack {
            Form { DraftAttachmentsView(attachments: $drafts, loading: $loadingAttachment) }
                .navigationTitle("Allegati")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Salva") { save() }.disabled(!loaded || loadingAttachment) }
                }
                .task {
                    do {
                        drafts = try (transaction.attachments ?? []).map {
                            guard let data = $0.data else { throw AttachmentFailure.format }
                            return try AttachmentDraft(id: $0.id, filename: $0.filename, data: data)
                        }
                        loaded = true
                    } catch { self.error = "Alcuni allegati non sono disponibili. Attendi la sincronizzazione e riprova." }
                }
                .alert("Impossibile salvare", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button("OK") { error = nil }
                } message: { Text(error ?? "") }
        }
    }
    private func save() {
        let editor = ModelContext(context.container)
        editor.autosaveEnabled = false
        let id = transaction.id
        do {
            guard let target = try editor.fetch(FetchDescriptor<FinanceTransaction>(predicate: #Predicate { $0.id == id })).first else { throw AttachmentFailure.format }
            let existing = target.attachments ?? []
            let kept = Set(drafts.map(\.id))
            for item in existing where !kept.contains(item.id) { editor.delete(item) }
            let existingIDs = Set(existing.map(\.id))
            for draft in drafts where !existingIDs.contains(draft.id) {
                let attachment = draft.model()
                editor.insert(attachment)
                attachment.transaction = target
            }
            try editor.save()
            dismiss()
        } catch { editor.rollback(); self.error = error.localizedDescription }
    }
}

/// File, photo and receipt-reading plumbing shared by both presentations of the draft attachments.
private struct AttachmentImportModifiers: ViewModifier {
    @Binding var attachments: [AttachmentDraft]
    @Binding var reading: AttachmentDraft?
    @Binding var importing: Bool
    @Binding var selectedPhoto: PhotosPickerItem?
    @Binding var loading: Bool
    @Binding var error: String?
    let onSelectAmount: ((Decimal) -> Void)?

    func body(content: Content) -> some View {
        content
            .sheet(item: $reading) { ReceiptReviewView(attachment: $0, onSelectAmount: onSelectAmount) }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.image, .pdf], allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls):
                    guard attachments.count + urls.count <= 5 else { error = AttachmentFailure.count.localizedDescription; return }
                    loading = true
                    Task {
                        do {
                            let loaded = try await Task.detached(priority: .userInitiated) {
                                try urls.map { url in
                                    let access = url.startAccessingSecurityScopedResource()
                                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                                    guard size <= 10 * 1024 * 1024 else { throw AttachmentFailure.size }
                                    return try AttachmentDraft(filename: url.lastPathComponent, data: Data(contentsOf: url))
                                }
                            }.value
                            guard attachments.count + loaded.count <= 5 else { throw AttachmentFailure.count }
                            attachments.append(contentsOf: loaded)
                        } catch { self.error = error.localizedDescription }
                        loading = false
                    }
                case .failure(let error): self.error = error.localizedDescription
                }
            }
            .task(id: selectedPhoto) {
                guard let selectedPhoto else { return }
                loading = true
                defer { loading = false; self.selectedPhoto = nil }
                do {
                    guard let data = try await selectedPhoto.loadTransferable(type: Data.self) else { throw AttachmentFailure.format }
                    try Task.checkCancellation()
                    guard attachments.count < 5 else { throw AttachmentFailure.count }
                    let ext = selectedPhoto.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                    attachments.append(try AttachmentDraft(filename: "Scontrino.\(ext)", data: data))
                } catch is CancellationError { }
                catch { self.error = error.localizedDescription }
            }
            .alert("Allegato non aggiunto", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
    }
}

/// A preview of a draft attachment: tap to read the receipt, the corner button removes it.
private struct AttachmentThumbnail: View {
    let attachment: AttachmentDraft
    let onRead: () -> Void
    let onRemove: () -> Void

    private var isPDF: Bool { attachment.contentType == UTType.pdf.identifier }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: onRead) {
                preview
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(ForgiaPalette.border, lineWidth: 0.7)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "text.viewfinder")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ForgiaPalette.accent)
                            .padding(5)
                            .background(ForgiaPalette.surface.opacity(0.9), in: Circle())
                            .padding(5)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Leggi scontrino \(attachment.filename)")

            Text(attachment.filename)
                .font(.caption2)
                .foregroundStyle(ForgiaPalette.mutedText)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 84, alignment: .leading)
        }
        .overlay(alignment: .topTrailing) {
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(ForgiaPalette.onAccent, Color.black.opacity(0.55))
            }
            .buttonStyle(.plain)
            .offset(x: 7, y: -7)
            .accessibilityLabel("Rimuovi \(attachment.filename)")
        }
    }

    @ViewBuilder
    private var preview: some View {
        #if os(iOS)
        if !isPDF, let image = UIImage(data: attachment.data) {
            Image(uiImage: image).resizable().scaledToFill()
        } else { placeholder }
        #else
        if !isPDF, let image = NSImage(data: attachment.data) {
            Image(nsImage: image).resizable().scaledToFill()
        } else { placeholder }
        #endif
    }

    private var placeholder: some View {
        ZStack {
            ForgiaPalette.canvas
            Image(systemName: isPDF ? "doc.richtext" : "doc")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(ForgiaPalette.accent)
        }
    }
}

/// Where a new attachment comes from, in the shape of the other quick-action tiles.
private struct AttachmentSourceTile: View {
    let title: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ForgiaPalette.accent)
                .frame(width: 36, height: 36)
                .background(tint, in: Circle())
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.primary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 74)
        .background(ForgiaPalette.canvas.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}
