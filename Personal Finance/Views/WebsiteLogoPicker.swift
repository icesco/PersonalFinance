import SwiftUI
import FinanceCore
import ImageIO

struct WebsiteLogoPicker: View {
    let initialQuery: String
    let onSelect: (Data) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var retryID = UUID()
    @State private var requestedSite: String?
    @State private var logos: [WebsiteLogo] = []
    @State private var selected: WebsiteLogo?
    @State private var previewData: Data?
    @State private var removeBackground = false
    @State private var loading = false
    @State private var processing = false
    @State private var error: String?
    @State private var initialized = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Banca, circuito o sito web", text: $query)
#if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
#endif
                        .accessibilityIdentifier("conto-logo-search-query")
                    Text("Cerca tra i marchi disponibili oppure inserisci il sito ufficiale, ad esempio banca.it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let selectedLogo = selected, let imageData = previewData {
                    WebsiteLogoPreview(data: imageData, domain: selectedLogo.source.host ?? "",
                        removeBackground: Binding(get: { removeBackground }, set: {
                            self.previewData = nil; processing = true; removeBackground = $0
                        }), processing: processing)
                }
                if loading {
                    Section { HStack { ProgressView(); Text("Cerco le immagini sul sito…") } }
                }
                if let errorMessage = error {
                    Section {
                        Text(errorMessage).foregroundStyle(.secondary)
                        if requestedSite != nil {
                            Button("Riprova") { self.error = nil; retryID = UUID() }
                        }
                    }
                }
                if !logos.isEmpty {
                    Section("Scegli il logo") {
                        ForEach(logos) { logo in
                            Button {
                                guard selected?.id != logo.id else { return }
                                previewData = nil
                                selected = logo
                                removeBackground = false
                            } label: {
                                WebsiteLogoResult(logo: logo, selected: selected?.id == logo.id)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                WebsiteLogoSources(query: query, loading: loading) { domain in
                    selected = nil; previewData = nil; logos = []; error = nil
                    retryID = UUID()
                    requestedSite = domain
                }
            }
            .navigationTitle("Cerca logo")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Usa logo") {
                        guard let previewData else { return }
                        onSelect(previewData)
                        dismiss()
                    }
                    .disabled(previewData == nil || processing || loading)
                    .accessibilityIdentifier("conto-logo-apply")
                }
            }
            .onAppear {
                guard !initialized else { return }
                // Account names stay local; only the chosen public website is requested.
                query = initialQuery
                initialized = true
            }
            .task(id: LogoSiteRequest(site: requestedSite, retryID: retryID)) {
                guard let requestedSite else { return }
                loading = true
                defer { loading = false }
                do {
                    let result = try await WebsiteLogoService.shared.logos(for: requestedSite)
                    try Task.checkCancellation()
                    logos = result
                } catch is CancellationError { }
                catch _ {
                    guard !Task.isCancelled else { return }
                    self.error = "Non ho trovato immagini utilizzabili su questo sito. Puoi provare un altro sito oppure caricare il logo da Foto o File."
                }
            }
            .task(id: LogoPreviewRequest(source: selected?.id, removeBackground: removeBackground)) {
                guard let selected else { previewData = nil; return }
                processing = true
                defer { processing = false }
                do {
                    let bytes = selected.data
                    let remove = removeBackground
                    let output = try await Task.detached(priority: .userInitiated) {
                        try Task.checkCancellation()
                        return remove ? try AccountLogoImage.removingLightBackground(bytes) : bytes
                    }.value
                    try Task.checkCancellation()
                    previewData = output
                } catch is CancellationError { }
                catch _ {
                    guard !Task.isCancelled else { return }
                    previewData = selected.data
                    removeBackground = false
                }
            }
        }
#if os(macOS)
        .frame(minWidth: 480, minHeight: 560)
#endif
    }
}

private struct LogoSiteRequest: Equatable {
    let site: String?
    let retryID: UUID
}

private struct LogoPreviewRequest: Equatable {
    let source: URL?
    let removeBackground: Bool
}

private struct WebsiteLogoSources: View {
    let query: String
    let loading: Bool
    let onSelect: (String) -> Void

    var body: some View {
        Section("Banche e carte") {
            ForEach(LogoBrand.matching(query)) { brand in
                Button { onSelect(brand.domain) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(brand.name).foregroundStyle(.primary)
                        Text(brand.domain).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("conto-logo-brand-\(brand.id)")
            }
            if let site = WebsiteLogoService.siteURL(query), let domain = site.host {
                Button { onSelect(domain) } label: {
                    Label("Cerca su \(domain)", systemImage: "globe")
                }
                .accessibilityIdentifier("conto-logo-website")
            } else if !query.isEmpty && LogoBrand.matching(query).isEmpty {
                Text("Marchio non presente? Inserisci il suo sito ufficiale.").foregroundStyle(.secondary)
            }
        }
        .disabled(loading)
    }
}

private struct WebsiteLogoResult: View {
    let logo: WebsiteLogo
    let selected: Bool
    var body: some View {
        HStack(spacing: 12) {
            ContoLogo(data: logo.data, symbol: "photo", color: AccountPalette.fallback, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(logo.source.host ?? "Logo").font(.subheadline).foregroundStyle(.primary)
                Text(logo.source.lastPathComponent).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(ForgiaPalette.accent) }
        }
        .padding(.vertical, 4)
        .accessibilityLabel("Logo da \(logo.source.host ?? "sito web")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct WebsiteLogoPreview: View {
    let data: Data
    let domain: String
    @Binding var removeBackground: Bool
    let processing: Bool

    var body: some View {
        Section("Anteprima") {
            HStack {
                Spacer()
                LogoTransparencyPreview(data: data)
                    .frame(width: 112, height: 112)
                    .padding(12)
                    .background(ForgiaPalette.sageSurface, in: RoundedRectangle(cornerRadius: 16))
                Spacer()
            }
            Text(domain).font(.caption).foregroundStyle(.secondary)
            Toggle("Rimuovi sfondo chiaro", isOn: $removeBackground)
                .accessibilityIdentifier("conto-logo-remove-background")
            if processing { ProgressView() }
            Text("Controlla l’anteprima: il bianco può far parte del logo. Le parti bianche racchiuse nel disegno vengono conservate.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct LogoTransparencyPreview: View {
    let data: Data
    var body: some View {
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            Image(decorative: image, scale: 1).resizable().scaledToFit()
        }
    }
}
