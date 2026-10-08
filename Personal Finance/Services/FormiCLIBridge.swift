#if os(macOS)
import AppKit
import SwiftData
import FinanceCore

@MainActor
enum FormiCLIBridge {
    static func accepts(_ url: URL) -> Bool { url.scheme == "formi" && url.host == "cli" }

    static func handle(_ url: URL, storage: DataStorageManager, lock: AppLock) async {
        guard accepts(url), let id = UUID(uuidString: url.lastPathComponent) else { return }
        let pasteboard = NSPasteboard(name: .init(FormiCLIWire.pasteboardName(id)))
        func reply(_ payload: [String: Any]) {
            var response = payload
            response["requestID"] = id.uuidString
            response["version"] = 1
            if let data = try? JSONSerialization.data(withJSONObject: response, options: [.sortedKeys]) {
                pasteboard.clearContents()
                pasteboard.setData(data, forType: .init(FormiCLIWire.responseType))
            }
        }
        func fail(_ code: String, _ message: String) {
            reply(["ok": false, "error": ["code": code, "message": message]])
        }
        guard UserDefaults.standard.bool(forKey: FormiCLIWire.enabledKey) else {
            fail("cli_disabled", "Abilita CLI per AI nelle impostazioni di Formi, sezione Integrazioni.")
            return
        }
        guard lock.hasUnlockedInSession && !lock.isLocked else {
            fail("app_locked", "Apri e sblocca Formi prima di usare la CLI."); return
        }
        guard let data = pasteboard.data(forType: .init(FormiCLIWire.requestType)),
              data.count <= FormiCLIWire.maxBytes,
              let request = try? FormiCLIWire.decoder().decode(FormiCLIRequest.self, from: data),
              request.id == id, request.version == 1 else {
            fail("invalid_request", "Richiesta CLI non valida."); return
        }
        guard request.targetAppPath == Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL.path,
              request.targetConfiguration == FormiCLIInstaller.channel else {
            fail("wrong_app", "La richiesta è destinata a una copia diversa di Formi. Apri la copia corretta e riprova."); return
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(25))
        while storage.currentContainer == nil && ContinuousClock.now < deadline {
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
        }
        guard Date().timeIntervalSince(request.issuedAt) >= -5,
              Date().timeIntervalSince(request.issuedAt) <= 40 else {
            fail("request_expired", "Richiesta scaduta: riprova con gli stessi requestID."); return
        }
        guard UserDefaults.standard.bool(forKey: FormiCLIWire.enabledKey),
              lock.hasUnlockedInSession && !lock.isLocked else {
            fail("access_disabled", "CLI disabilitata o Formi bloccata."); return
        }
        guard let container = storage.currentContainer else {
            fail("app_not_ready", "Formi non ha ancora aperto i dati. Apri l'app e riprova."); return
        }
        do {
            let context = ModelContext(container)
            switch request.command {
            case "accounts", "categories":
                guard !request.commit, request.movements.isEmpty else {
                    throw FormiCLIService.Failure("La lettura non accetta movimenti o commit.")
                }
                let shared = Set(try context.fetch(FetchDescriptor<SharedBookMembership>()).map(\.localBookID))
                let books = try context.fetch(FetchDescriptor<Account>(sortBy: [SortDescriptor(\.name)]))
                    .filter { $0.isActive == true && (request.bookID == nil || request.bookID == $0.id) }
                let bookIDs = Set(books.map(\.id))
                if request.command == "accounts" {
                    let accounts = try context.fetch(FetchDescriptor<Conto>(sortBy: [SortDescriptor(\.name)]))
                        .filter { $0.isActive == true && $0.account.map { bookIDs.contains($0.id) } == true }
                    reply(["ok": true, "timeZone": TimeZone.current.identifier,
                           "accounts": accounts.map { conto -> [String: Any] in
                        ["id": conto.id.uuidString, "name": conto.name ?? "Conto",
                         "bookID": conto.account!.id.uuidString, "book": conto.account!.name ?? "Libro",
                         "currency": conto.account!.currency ?? "", "writable": !shared.contains(conto.account!.id)]
                    }])
                } else {
                    let categories = try context.fetch(FetchDescriptor<FinanceCore.Category>(sortBy: [SortDescriptor(\.name)]))
                        .filter { $0.isActive == true && $0.account.map { bookIDs.contains($0.id) } == true }
                    reply(["ok": true, "categories": categories.map { category -> [String: Any] in
                        ["id": category.id.uuidString, "name": category.name ?? "Categoria",
                         "bookID": category.account!.id.uuidString, "type": category.kindRaw ?? "both"]
                    }])
                }
            default:
                let result = try FormiCLIService.execute(request, container: container)
                let encoded = try FormiCLIWire.encoder().encode(result)
                reply(["ok": true, "result": try JSONSerialization.jsonObject(with: encoded)])
            }
        } catch { fail("invalid_request", error.localizedDescription) }
    }
}
#endif
