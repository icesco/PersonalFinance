import Foundation
import AppKit

@main
struct FormiCLI {
    static var channel: String {
        #if DEBUG
        "debug"
        #else
        "release"
        #endif
    }
    static var commandName: String { channel == "debug" ? "formi-debug" : "formi" }
    static let aiHelp = """
    Formi: istruzioni per assistenti AI
    1. Esegui info e verifica appPath, configuration e versione dell'app prima di usare i dati.
       Usa formi per Release e formi-debug per Debug. I nomi non isolano il database.
    2. Leggi schema e --help. Esegui accounts e categories: non inventare UUID,
       valuta, conto, categoria o data. Se la selezione è ambigua chiedi all'utente.
    3. Prepara i movimenti con importi decimali positivi come stringhe, date YYYY-MM-DD
       nel fuso restituito da accounts e un UUID requestID stabile per ogni movimento.
       Per automazioni usa sempre --request-id e --date espliciti anche con add.
    4. Esegui add/import senza --yes, oppure preview: non salvano movimenti.
       Mostra conto, tipo, importo, valuta, data, descrizione e possibili duplicati.
    5. Solo dopo l'autorizzazione dell'utente ripeti gli stessi dati con --yes.
       Non usare --allow-duplicates senza autorizzazione esplicita.
    6. Se ok è false o l'exit code è 1, non dichiarare che il salvataggio è riuscito.
       Dopo un timeout il salvataggio potrebbe essere avvenuto: riusa gli stessi
       requestID e dati. Non generare nuovi UUID per ritentare un movimento.
       alreadyRecorded significa che la richiesta era già stata registrata:
       non ricreare movimenti successivamente modificati o eliminati.
    7. Il lotto è atomico (1–500 movimenti, massimo 2 MB). La CLI supporta solo
       spese ed entrate nei libri personali, senza conversioni implicite, trasferimenti,
       allegati o ricorrenze. saved prova il salvataggio locale, non la sincronizzazione cloud.
    8. Per categorie usa category-create o category-update con --book e un nuovo
       --request-id stabile per ciascuna operazione. categories --include-archived
       mostra anche gli archiviati, parentID, type, active, color e icon.
       I campi omessi si conservano. --parent none promuove a principale, --parent UUID
       sposta sotto una principale dello stesso libro. Non cambiare libro o UUID.
       Prima anteprima senza --yes: mostra tutti i changes (before/after), anche figli.
       Dopo autorizzazione ripeti gli stessi campi con --revision della risposta e --yes.
       Conserva anche revision sui retry. alreadyRecorded non prova lo stato attuale:
       rileggi categories; non ripristinare automaticamente modifiche successive.
       Se revision è scaduta rifai l'anteprima e sottoponi i nuovi effetti all'utente.
       Il tipo dei figli segue il genitore; cambiare il tipo può essere rifiutato per
       movimenti incompatibili. Archiviare una principale archivia i figli; riattivarla
       non li riattiva. Sposta prima tutti i figli per rendere una principale figlia.
       Nomi uguali fra fratelli sono rifiutati anche se archiviati. Colori #RRGGBB,
       icone SF Symbols disponibili sul Mac. Nessuna eliminazione definitiva.
    9. Non aggirare CLI disabilitata, blocco privacy, wrong_app o altre validazioni.
       Chiedi all'utente di aprire la copia corretta di Formi e risolvere il problema.
    """
    static let help = """
    Formi CLI — movimenti per assistenti AI esterni

    formi accounts [--book UUID]
    formi categories [--book UUID] [--include-archived]
    formi add --account UUID --amount 25.50 --currency EUR
              [--category UUID] [--description "Spesa"] [--date YYYY-MM-DD]
              [--request-id UUID] [--type expense|income] [--yes] [--allow-duplicates]
    formi preview movimenti.json
    formi import movimenti.json [--yes] [--allow-duplicates]
    formi import - < movimenti.json
    formi category-create --book UUID --name "Categoria" --request-id UUID
              [--parent UUID|none] [--type expense|income|both]
              [--color '#RRGGBB'] [--icon SF_SYMBOL] [--active true|false]
              [--revision TOKEN --yes]
    formi category-update --book UUID --category UUID --request-id UUID
              [--name "Nome"] [--parent UUID|none] [--type expense|income|both]
              [--color '#RRGGBB'] [--icon SF_SYMBOL] [--active true|false]
              [--revision TOKEN --yes]
    formi schema
    formi info
    formi ai-help

    add e import restituiscono un'anteprima; --yes salva tutti i movimenti.
    Le categorie richiedono --request-id stabile e --book. Prima esegui l'anteprima,
    poi ripeti con --revision restituita e --yes. I campi omessi sono conservati.
    --parent none rende principale; il tipo dei figli è ereditato dal genitore.
    Archivio (--active false) di una principale archivia i figli; riattivarla
    non riattiva automaticamente i figli. La gerarchia ha due livelli.
    Le risposte sono JSON. --json è accettato per compatibilità.
    Ogni movimento JSON richiede requestID, accountID, type, amount (stringa),
    currency e date (YYYY-MM-DD); categoryID e description sono facoltativi.
    Riusa lo stesso requestID e gli stessi dati nei tentativi successivi.
    Abilita la CLI in Formi > Impostazioni > Integrazioni > CLI per AI.
    """

    @MainActor static func main() async {
        do {
            var arguments = Array(CommandLine.arguments.dropFirst())
            // Installed launchers pin their channel even if another build replaces the app in place.
            if arguments.first == "--expect-channel" {
                guard arguments.count >= 2, arguments[1] == channel else {
                    throw FormiCLIArguments.Failure("Il launcher non corrisponde alla configurazione dell'app. Reinstalla la CLI dalla copia Debug o Release corretta.")
                }
                arguments.removeFirst(2)
            }
            if arguments.isEmpty || arguments == ["--help"] || arguments == ["help"] {
                print(help.replacingOccurrences(of: "formi ", with: "\(commandName) ")); return
            }
            if arguments == ["ai-help"] || arguments == ["--help", "--ai"] {
                print(aiHelp); return
            }
            if arguments == ["--version"] || arguments == ["info"] || arguments == ["--version", "--json"] {
                let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
                let appURL = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL
                let bundle = Bundle(url: appURL)
                let metadata: [String: Any] = ["cliVersion": "1.1", "protocolVersion": 1,
                    "command": commandName, "configuration": channel, "appPath": appURL.path,
                    "appVersion": bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                    "appBuild": bundle?.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
                    "bundleIdentifier": bundle?.bundleIdentifier ?? "unknown"]
                print(String(decoding: try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys]), as: UTF8.self)); return
            }
            if arguments == ["schema"] {
                print(##"{"version":1,"maxBatchSize":500,"commands":["info","ai-help","accounts","categories","add","preview","import","category-create","category-update"],"categoryMutation":{"required":["bookID","requestID"],"create":"name required; categoryID assigned from requestID","update":"categoryID required; omitted fields preserved","fields":{"name":"1-200 characters","color":"#RRGGBB","icon":"SF Symbol","parent":"UUID or none","type":"expense|income|both (children inherit)","active":"true|false"},"commit":"preview first, then same arguments with --revision TOKEN --yes","hierarchyLevels":2,"archive":"root also archives children; reactivate individually","retry":"same requestID, fields and revision; alreadyRecorded never reapplies","list":"categories --include-archived includes parentID, type, active, icon, color"},"movement":{"requestID":"UUID (stable on retries)","accountID":"UUID from accounts","categoryID":"optional UUID from categories","type":"expense|income","amount":"positive decimal string, e.g. 25.50","currency":"account currency, e.g. EUR","date":"YYYY-MM-DD in Formi's local time zone","description":"optional string"},"writes":"add/import require --yes","transfers":false}"##)
                return
            }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.dateFormat = "yyyy-MM-dd"
            var request = try FormiCLIArguments.parse(arguments, read: { path in
                let handle = path == "-" ? FileHandle.standardInput
                    : try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
                defer { if path != "-" { try? handle.close() } }
                var data = Data()
                while data.count <= FormiCLIWire.maxBytes {
                    let remaining = FormiCLIWire.maxBytes + 1 - data.count
                    guard let chunk = try handle.read(upToCount: min(65_536, remaining)), !chunk.isEmpty else { break }
                    data.append(chunk)
                }
                return data
            }, today: formatter.string(from: Date()))
            let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
            let appURL = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL
            guard appURL.pathExtension == "app" else {
                throw FormiCLIArguments.Failure("Esegui la CLI inclusa in Formi.app/Contents/MacOS/formi.")
            }
            request.targetAppPath = appURL.path
            request.targetConfiguration = channel
            let pasteboard = NSPasteboard(name: .init(FormiCLIWire.pasteboardName(request.id)))
            defer { pasteboard.releaseGlobally() }
            let data = try FormiCLIWire.encoder().encode(request)
            guard data.count <= FormiCLIWire.maxBytes else { throw FormiCLIArguments.Failure("Richiesta troppo grande.") }
            pasteboard.clearContents()
            guard pasteboard.setData(data, forType: .init(FormiCLIWire.requestType)) else {
                throw FormiCLIArguments.Failure("Impossibile inviare la richiesta a Formi.")
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            let url = URL(string: "formi://cli/\(request.id.uuidString)")!
            _ = try await NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration)
            let deadline = ContinuousClock.now.advanced(by: .seconds(45))
            while ContinuousClock.now < deadline {
                if let response = pasteboard.data(forType: .init(FormiCLIWire.responseType)),
                   let json = try JSONSerialization.jsonObject(with: response) as? [String: Any],
                   json["requestID"] as? String == request.id.uuidString {
                    FileHandle.standardOutput.write(response)
                    print("")
                    if json["ok"] as? Bool != true { exit(1) }
                    return
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            throw FormiCLIArguments.Failure("Formi non ha risposto. Apri l'app e verifica la CLI e il blocco privacy. Se avevi usato --yes, riprova con gli stessi requestID: la richiesta potrebbe essere stata salvata.")
        } catch {
            let json: [String: Any] = ["ok": false, "error": ["code": "cli_error", "message": error.localizedDescription]]
            if let data = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]) {
                FileHandle.standardOutput.write(data); print("")
            }
            exit(1)
        }
    }
}
