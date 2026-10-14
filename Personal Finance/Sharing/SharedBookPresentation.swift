import SwiftUI
import FinanceCore

struct SharedBookPanel<Content: View>: View {
    var title: LocalizedStringKey?
    var cardLayout: Bool
    @ViewBuilder let content: Content

    init(_ title: LocalizedStringKey? = nil, cardLayout: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self.cardLayout = cardLayout
        self.content = content()
    }

    var body: some View {
        if cardLayout {
            VStack(alignment: .leading, spacing: 14) {
                if let title {
                    Text(title)
                        .font(.system(.title3, design: .serif, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                }
                content
            }
            .unifiedCard()
        } else {
            Section {
                content
            } header: {
                if let title { Text(title) }
            }
        }
    }
}

struct SharedBookOverview: View {
    let name: String
    let isContoShare: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
            layout {
                FormiFeatureIllustration(artwork: isContoShare ? .sharedAccount : .sharedBook, size: 88)
                VStack(alignment: .leading, spacing: 5) {
                    Text(isContoShare ? "Condivisione del conto" : "Condivisione del libro")
                        .font(.subheadline).foregroundStyle(ForgiaPalette.mutedText)
                    Text(name)
                        .font(.system(.title2, design: .serif, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(isContoShare
                 ? "Condividi questo conto e i suoi movimenti con le persone che inviti."
                 : "Condividi conti, movimenti, budget, ricorrenze e allegati di questo libro con le persone che inviti.")
                .font(.subheadline).foregroundStyle(ForgiaPalette.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .unifiedCard(tint: ForgiaPalette.accent)
    }
}

struct SharedBookInvitationCard<Feedback: View>: View {
    let isContoShare: Bool
    let isOwner: Bool
    let isShared: Bool
    let enabled: Bool
    let busy: Bool
    @Binding var personName: String
    let onInvite: () -> Void
    let onSync: () -> Void
    @ViewBuilder let feedback: Feedback

    var body: some View {
        SharedBookPanel("Persone invitate", cardLayout: true) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Come compari nei movimenti").font(.subheadline.weight(.medium))
                TextField("Il tuo nome", text: $personName,
                          prompt: Text("Il tuo nome").foregroundStyle(ForgiaPalette.mutedText))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 48)
                    .cardInset()
                    .accessibilityIdentifier("shared-book-person-name")
                Text("Serve a riconoscere chi registra i movimenti e chi effettua i versamenti.")
                    .font(.footnote).foregroundStyle(ForgiaPalette.mutedText)
            }

            if !enabled {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Sincronizzazione iCloud disattivata", systemImage: "icloud.slash")
                        .font(.subheadline.weight(.medium))
                    Text("Attiva iCloud nelle impostazioni di Formi per condividere o aggiornare i dati.")
                        .font(.footnote).foregroundStyle(ForgiaPalette.mutedText)
                }
                .fixedSize(horizontal: false, vertical: true)
            }

            if isOwner {
                Button(action: onInvite) {
                    HStack(spacing: 8) {
                        FormiFeatureIcon(symbol: isContoShare ? .sharedAccount : .sharedBook,
                                         size: 24, ink: enabled && !busy ? ForgiaPalette.onAccent : ForgiaPalette.mutedText)
                        Text(isShared ? "Gestisci invitati" : (isContoShare ? "Condividi conto" : "Condividi libro"))
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(SharedBookInviteButtonStyle())
                .disabled(!enabled || busy)
                .accessibilityIdentifier("shared-book-invite")
            } else {
                Label {
                    Text(isContoShare ? "Conto ricevuto" : "Libro ricevuto")
                } icon: {
                    FormiFeatureIcon(symbol: isContoShare ? .sharedAccount : .sharedBook, size: 26)
                }
                Text("Gli inviti sono gestiti dal proprietario della condivisione.")
                    .font(.subheadline).foregroundStyle(ForgiaPalette.mutedText)
            }
            if isShared {
                Button("Sincronizza adesso", systemImage: "arrow.triangle.2.circlepath", action: onSync)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .buttonStyle(.bordered)
                    .disabled(!enabled || busy)
                    .accessibilityIdentifier("shared-book-sync")
            }
            feedback
        }
    }
}

private struct SharedBookInviteButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 48)
            .foregroundStyle(isEnabled ? ForgiaPalette.onAccent : ForgiaPalette.mutedText)
            .background(isEnabled ? ForgiaPalette.accent : ForgiaPalette.sageSurface, in: Capsule())
            .contentShape(Capsule())
            .opacity(configuration.isPressed && isEnabled ? 0.8 : 1)
    }
}

struct SharedBookSyncFeedback: View {
    let message: String?
    let busy: Bool
    let status: SharedBookAutomaticRefresh.Status?

    var body: some View {
        if busy { ProgressView("Aggiornamento della condivisione…") }
        if let message {
            Text(message).font(.callout).accessibilityIdentifier("shared-book-status")
        } else {
            switch status {
            case let .updated(date):
                Text("Aggiornamento automatico: \(date, format: .dateTime.hour().minute())")
                    .font(.callout).foregroundStyle(ForgiaPalette.mutedText)
            case .needsReview:
                Text("Ci sono differenze da verificare. Tocca Sincronizza adesso per confrontarle.")
                    .font(.callout)
            case .failed:
                Text("Aggiornamento automatico non riuscito. I dati locali restano disponibili; puoi riprovare con Sincronizza adesso.")
                    .font(.callout)
            case nil:
                EmptyView()
            }
        }
    }
}

struct SharedBookPrivacyCard: View {
    let isContoShare: Bool

    var body: some View {
        SharedBookPanel("Cosa resta privato", cardLayout: true) {
            Text(isContoShare
                 ? "I tuoi altri conti restano privati, anche se appartengono allo stesso libro."
                 : "I conti di altri libri restano privati.")
                .font(.subheadline).foregroundStyle(ForgiaPalette.mutedText)
            DisclosureGroup("Trasferimenti tra conti") {
                Text(isContoShare
                     ? "I trasferimenti mantengono il collegamento al tuo conto privato sul tuo dispositivo. Gli invitati vedono solo il movimento sul conto condiviso, senza note o allegati del trasferimento privato."
                     : "I trasferimenti mostrano soltanto la parte relativa a questo libro.")
                    .font(.footnote).foregroundStyle(ForgiaPalette.mutedText)
                    .padding(.top, 8)
            }
            .font(.subheadline)
            .frame(minHeight: 44)
            DisclosureGroup("Come si aggiorna la condivisione") {
                Text("I conti e i libri già condivisi si aggiornano automaticamente mentre Formi è aperta e sbloccata, con iCloud attivo. Puoi anche usare Sincronizza adesso. La prima condivisione carica i dati su iCloud prima di aprire gli inviti.")
                    .font(.footnote).foregroundStyle(ForgiaPalette.mutedText)
                    .padding(.top, 8)
            }
            .font(.subheadline)
            .frame(minHeight: 44)
        }
    }
}

struct SharedContoCategoriesCard: View {
    let conto: Conto

    var body: some View {
        SharedBookPanel("Categorie del conto", cardLayout: true) {
            Text("Questo conto ha un elenco di categorie condiviso con le persone invitate.")
                .font(.subheadline).foregroundStyle(ForgiaPalette.mutedText)
            if conto.usesSharedCategories == true {
                NavigationLink {
                    SharedContoCategoriesView(conto: conto)
                } label: {
                    HStack {
                        Text("Gestisci categorie condivise")
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    }
                    .frame(minHeight: 44)
                }
                .accessibilityIdentifier("shared-book-categories")
            }
            DisclosureGroup("Come funzionano le categorie") {
                Text("Alla condivisione, Formi copia nell’elenco le categorie già usate dai suoi movimenti. Puoi anche creare nuove categorie dedicate al conto. Le copie sono indipendenti: le categorie personali originali restano invariate.")
                    .font(.footnote).foregroundStyle(ForgiaPalette.mutedText)
                    .padding(.top, 8)
            }
            .font(.subheadline)
            .frame(minHeight: 44)
        }
    }
}
