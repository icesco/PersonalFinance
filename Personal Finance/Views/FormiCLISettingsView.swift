#if os(macOS)
import SwiftUI
import AppKit
import FinanceCore

struct FormiCLISettingsView: View {
    @AppStorage(FormiCLIWire.enabledKey) private var enabled = false
    @AppStorage(FormiCLIInstaller.installationPathKey) private var installedPath = ""
    @State private var installationMessage: String?
    @State private var installationError: String?
    @State private var isInstalling = false
    private var executableURL: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/formi") }
    private var commandPath: String { installedPath.isEmpty ? executableURL.path : installedPath }
    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
    var body: some View {
        Form {
            Section("Installa il comando") {
                Text("Installa la CLI solo quando vuoi usarla. Il comando di questa build è \(FormiCLIInstaller.commandName): formi per Release, formi-debug per Debug. L'app non lo installa all'avvio o durante gli aggiornamenti.")
                    .foregroundStyle(.secondary)
                Text("Il nome distingue la copia dell'app, ma non crea un archivio di prova separato.")
                    .foregroundStyle(.secondary)
                Button("Installa CLI…", systemImage: "terminal") { Task { await install() } }
                    .disabled(isInstalling)
                    .accessibilityIdentifier("formi-cli-install")
                if !installedPath.isEmpty {
                    LabeledContent("Ultima installazione") {
                        Text(installedPath).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    }
                    Text("Se la cartella scelta non è nel PATH, copia il comando qui sotto nel terminale. Dopo uno spostamento dell'app, reinstalla la CLI per aggiornare il collegamento.")
                        .foregroundStyle(.secondary)
                }
                if let installationMessage {
                    Text(installationMessage).accessibilityIdentifier("formi-cli-install-success")
                }
            }
            Section {
                Toggle("Abilita CLI per AI esterne", isOn: $enabled)
                    .accessibilityIdentifier("formi-cli-enabled")
                Text("Consenti agli assistenti che usi su questo Mac di leggere conti e categorie, aggiungere movimenti e creare o modificare categorie. Se usi il blocco privacy, sblocca prima Formi.")
                    .foregroundStyle(.secondary)
            }
            Section("Collega il tuo assistente") {
                Text("Dopo l'installazione, copia le istruzioni per il tuo assistente AI. Puoi anche usare direttamente la CLI inclusa nell'app tramite il suo percorso completo.")
                Text(commandPath).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                HStack {
                    Button("Copia percorso") { copy(commandPath) }
                    Button("Copia comando PATH") {
                        let directory = URL(fileURLWithPath: commandPath).deletingLastPathComponent().path
                        copy("export PATH=\(FormiCLIInstaller.shellQuote(directory)):\"$PATH\"")
                    }
                    Button("Copia istruzioni per l'AI") {
                        copy("""
                        Usa la CLI di Formi a questo percorso: \(FormiCLIInstaller.shellQuote(commandPath)).
                        Leggi info, ai-help, --help e schema. Verifica che appPath e configuration corrispondano alla copia dell'app desiderata.
                        Usa accounts e categories per conoscere gli UUID reali.
                        Per una spesa usa add; per più movimenti usa import con JSON da file o stdin.
                        Per categorie usa category-create e category-update: mostra gli effetti sui figli e salva con --revision dell’anteprima e --yes.
                        Gli importi sono stringhe decimali positive; le date sono YYYY-MM-DD nel fuso indicato da accounts.
                        Mostra l'anteprima e chiedimi conferma prima di salvare con --yes.
                        Conserva requestID e tutti i dati invariati durante i tentativi successivi, anche dopo un timeout.
                        Controlla i possibili duplicati; non usare --allow-duplicates senza una mia richiesta esplicita.
                        """)
                    }
                }
            }
            Section("Una spesa o un intero lotto") {
                Text("\(FormiCLIInstaller.commandName) add --account UUID --amount 25.50 --currency EUR --description 'Spesa'\n\(FormiCLIInstaller.commandName) import movimenti.json\n\(FormiCLIInstaller.commandName) import movimenti.json --yes")
                    .font(.system(.body, design: .monospaced)).textSelection(.enabled)
                Text("Senza --yes viene mostrata solo l'anteprima. Il salvataggio verifica l'intero lotto e i possibili duplicati. Puoi inserire spese ed entrate nei libri personali, fino a 500 movimenti per richiesta.")
                    .foregroundStyle(.secondary)
            }
            Section("Categorie e sottocategorie") {
                Text("\(FormiCLIInstaller.commandName) categories --include-archived\n\(FormiCLIInstaller.commandName) category-create --book UUID --name 'Viaggi' --request-id UUID\n\(FormiCLIInstaller.commandName) category-update --book UUID --category UUID --parent UUID --request-id UUID")
                    .font(.system(.body, design: .monospaced)).textSelection(.enabled)
                Text("Puoi modificare nome, tipo, icona, colore, stato e gerarchia a due livelli. Prima controlla l'anteprima, inclusi gli effetti sui figli; poi ripeti con --revision restituita e --yes. I movimenti e i budget mantengono i riferimenti alla categoria.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("CLI per AI")
        .alert("Installazione CLI", isPresented: Binding(
            get: { installationError != nil }, set: { if !$0 { installationError = nil } }
        )) {
            Button("OK", role: .cancel) { installationError = nil }
        } message: {
            Text(installationError ?? "")
        }
    }

    private func install() async {
        guard !isInstalling else { return }
        isInstalling = true
        defer { isInstalling = false }
        installationMessage = nil
        do {
            guard let destination = try await FormiCLIInstaller.install(executable: executableURL, previousPath: installedPath) else { return }
            installedPath = destination.path
            installationMessage = "CLI installata. Abilita l'accesso ai dati per usarla con il tuo assistente."
        } catch { installationError = error.localizedDescription }
    }
}
#endif
