import SwiftUI

struct SharedBookLeaveSection: View {
    let enabled: Bool
    let busy: Bool
    let onLeave: () -> Void
    @State private var confirming = false

    var body: some View {
        Section {
            Button("Lascia la condivisione", role: .destructive) { confirming = true }
                .disabled(!enabled || busy)
                .accessibilityIdentifier("shared-book-leave")
                .confirmationDialog("Lasciare la condivisione?", isPresented: $confirming, titleVisibility: .visible) {
                    Button("Lascia e conserva una copia", role: .destructive, action: onLeave)
                    Button("Annulla", role: .cancel) { }
                } message: {
                    Text("Il libro degli altri partecipanti resterà disponibile. La tua copia includerà soltanto i dati già presenti su questo dispositivo, comprese le modifiche non ancora inviate.")
                }
            Text("Conserverai una copia privata con i dati presenti su questo dispositivo. Le modifiche successive non verranno più condivise.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
/// Exercises the production confirmation control without calling CloudKit.
struct SharedBookLeaveFixture: View {
    @State private var confirmed = false
    var body: some View {
        NavigationStack {
            List {
                if confirmed { Text("Conferma ricevuta localmente.").accessibilityIdentifier("leave-fixture-confirmed") }
                else { SharedBookLeaveSection(enabled: true, busy: false) { confirmed = true } }
            }.navigationTitle("Condivisione")
        }
    }
}
#endif
