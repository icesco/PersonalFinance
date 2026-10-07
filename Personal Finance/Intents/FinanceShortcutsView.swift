import AppIntents
import SwiftUI

struct FinanceShortcutsView: View {
    var body: some View {
        List {
            Section("Azioni disponibili") {
                Label("Acquisisci notifica bancaria", systemImage: "tray.and.arrow.down")
                NavigationLink("Configura l’automazione", destination: CaptureSetupView())
                CaptureInboxEntry()
                Label("Prepara una spesa", systemImage: "plus.circle")
                Label("Apri il riepilogo di oggi", systemImage: "house")
                Label("Apri budget e scadenze", systemImage: "calendar")
            }
            Section {
                Text("Nell’app Comandi Rapidi cerca Formi. Aggiungi “Prepara una spesa” e, se vuoi, passa importo e descrizione da altre azioni.")
                Text("L’importo è nella valuta del libro selezionato. Usa la virgola o il punto per i decimali, senza simboli di valuta o separatori delle migliaia.")
                Text("Formi apre la spesa da completare: scegli conto e categoria, controlla i budget e salva. Se hai attivato il blocco, prima dovrai sbloccare l’app.")
                Button("Prova nuova spesa", intent: PrepareExpenseIntent())
                    .accessibilityIdentifier("try-expense-shortcut")
            } header: {
                Text("Come usarle")
            }
            Section("Con Siri") {
                Text("Puoi dire: “Prepara una spesa in Formi”, “Apri il riepilogo in Formi” oppure “Apri budget e scadenze in Formi”.")
            }
        }
        .navigationTitle("Comandi Rapidi e Siri")
    }
}
