import SwiftUI
import FinanceCore
import PhotosUI
import UniformTypeIdentifiers
import ImageIO

struct ContoLogo: View {
    @Environment(\.colorScheme) private var colorScheme
    let data: Data?
    let symbol: String
    let color: String
    let size: CGFloat

    init(conto: Conto, size: CGFloat = 32) {
        self.init(data: conto.logoData, symbol: conto.type?.icon ?? "creditcard", color: conto.displayColorHex, size: size)
    }

    init(data: Data?, symbol: String, color: String, size: CGFloat) {
        self.data = data; self.symbol = symbol; self.color = color; self.size = size
    }

    var body: some View {
        Group {
            if let data, let source = CGImageSourceCreateWithData(data as CFData, nil),
               let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                Image(decorative: image, scale: 1)
                    .resizable().scaledToFit()
                    .padding(size * 0.08)
                    .background {
                        if colorScheme == .dark {
                            // Keep dark brand marks readable; transparent logos blend into light account rows.
                            RoundedRectangle(cornerRadius: size * 0.2).fill(.white)
                        }
                    }
            } else {
                Image(systemName: symbol).foregroundStyle(Color(hex: color))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct ContoLogoEditor: View {
    @Binding var data: Data?
    @Binding var loading: Bool
    let symbol: String
    let color: String
    var accountName: String = ""
    @State private var searching = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var importing = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ContoLogo(data: data, symbol: symbol, color: color, size: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Logo della banca o della carta").font(.subheadline.weight(.medium))
                    Text("Cerca il logo oppure scegli un’immagine.").font(.caption).foregroundStyle(.secondary)
                }
                if loading { ProgressView().controlSize(.small) }
            }
            ViewThatFits {
                HStack { sourceButtons }
                VStack(alignment: .leading) { sourceButtons }
            }
            .buttonStyle(.borderless)
            .disabled(loading)
        }
        .sheet(isPresented: $searching) {
            WebsiteLogoPicker(initialQuery: accountName) { data = $0 }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { result in
            switch result {
            case .success(let url):
                loading = true
                Task {
                    defer { loading = false }
                    do {
                        let normalized = try await Task.detached(priority: .userInitiated) {
                            let access = url.startAccessingSecurityScopedResource()
                            defer { if access { url.stopAccessingSecurityScopedResource() } }
                            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                            guard size <= 10 * 1024 * 1024 else { throw AccountLogoImage.Failure.invalid }
                            return try AccountLogoImage.normalize(Data(contentsOf: url))
                        }.value
                        data = normalized
                    } catch { self.error = "Scegli un’immagine valida fino a 10 MB (ad esempio PNG o JPEG)." }
                }
            case .failure: error = "Non è stato possibile aprire l’immagine. Riprova."
            }
        }
        .task(id: selectedPhoto) {
            guard let selectedPhoto else { return }
            loading = true
            defer { loading = false }
            do {
                guard let bytes = try await selectedPhoto.loadTransferable(type: Data.self) else { throw AccountLogoImage.Failure.invalid }
                let normalized = try await Task.detached(priority: .userInitiated) { try AccountLogoImage.normalize(bytes) }.value
                try Task.checkCancellation()
                data = normalized
            } catch is CancellationError { }
            catch { self.error = "Non è stato possibile caricare il logo. Scegli un’altra immagine fino a 10 MB." }
        }
        .alert("Logo non aggiunto", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }

    @ViewBuilder private var sourceButtons: some View {
        Button { searching = true } label: { Label("Cerca logo", systemImage: "magnifyingglass") }
            .accessibilityIdentifier("conto-logo-search")
        PhotosPicker(selection: $selectedPhoto, matching: .images) {
            Label("Foto", systemImage: "photo")
        }.accessibilityIdentifier("conto-logo-photo")
        Button { importing = true } label: { Label("File", systemImage: "folder") }
            .accessibilityIdentifier("conto-logo-file")
        if data != nil {
            Button("Rimuovi logo", role: .destructive) { data = nil; selectedPhoto = nil }
                .accessibilityIdentifier("conto-logo-remove")
        }
    }
}
