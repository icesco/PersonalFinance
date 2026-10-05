import Foundation
import Observation
import WatchConnectivity

struct WatchRemoteState: Codable {
    var input: RemoteExpenseInput?
    var quote: RemoteExpenseQuote?
    var confirmationWasSent = false
    var savedID: UUID?
}

@MainActor @Observable
final class WatchConnection: NSObject, WCSessionDelegate {
    private(set) var overview = WatchOverview.redacted
    private(set) var isSending = false
    private(set) var message: String?
    private var requestToken: UUID?
    private var requestWasSave = false
    private(set) var remote = WatchRemoteState()
    private let remoteKey = "forgia.watch.remoteExpense.v1"

    func resetRemote() {
        guard !isSending, !remote.confirmationWasSent else { return }
        remote = WatchRemoteState()
        persistRemote()
        message = nil
    }
    func reviewExpense(book: WatchBook, contoID: UUID, categoryID: UUID, amount: String, note: String) {
        guard !isSending, !remote.confirmationWasSent else { return }
        let draft = WatchExpenseDraft(id: UUID(), bookID: book.id, amount: amount, note: note)
        guard draft.normalizedAmount != nil,
              let value = Decimal(string: amount.replacingOccurrences(of: ",", with: ".")) else {
            message = "Inserisci un importo positivo e una nota fino a 200 caratteri."; return
        }
        remote = WatchRemoteState(input: RemoteExpenseInput(requestID: UUID(), bookID: book.id,
            contoID: contoID, categoryID: categoryID, amount: value, currency: book.currency, date: Date(), note: note))
        persistRemote()
        send(WatchRequest(draft: nil, expense: remote.input))
    }
    func confirmExpense() {
        guard !isSending, let input = remote.input, let quote = remote.quote else { return }
        remote.confirmationWasSent = true
        persistRemote()
        send(WatchRequest(draft: nil, expense: input, confirmation: quote))
    }
    private func persistRemote() {
        if let data = try? JSONEncoder().encode(remote) { UserDefaults.standard.set(data, forKey: remoteKey) }
    }
    private let draftKey = "forgia.watch.unsentDraft.v1"
    private let snapshotKey = "forgia.watch.overview.v1"
    var pendingDraft: WatchExpenseDraft? {
        UserDefaults.standard.data(forKey: draftKey).flatMap { try? JSONDecoder().decode(WatchExpenseDraft.self, from: $0) }
    }

    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: remoteKey),
           let restored = try? JSONDecoder().decode(WatchRemoteState.self, from: data) { remote = restored }
        if let data = UserDefaults.standard.data(forKey: snapshotKey) { receiveOverview(data) }
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }
    func refresh() { send(WatchRequest(draft: nil)) }
    func prepare(amount: String, note: String, bookID: UUID?) {
        let existing = pendingDraft
        let draft = WatchExpenseDraft(id: existing?.amount == amount && existing?.note == note && existing?.bookID == bookID ? existing!.id : UUID(),
                                      bookID: bookID, amount: amount, note: note)
        guard draft.normalizedAmount != nil else { message = "Inserisci un importo positivo e una nota fino a 200 caratteri."; return }
        if let data = try? JSONEncoder().encode(draft) { UserDefaults.standard.set(data, forKey: draftKey) }
        send(WatchRequest(draft: draft))
    }
    private func send(_ request: WatchRequest) {
        guard !isSending else { return }
        guard WCSession.default.activationState == .activated, WCSession.default.isReachable else {
            message = "iPhone non raggiungibile. Apri Forgia sul telefono e riprova."
                + ((request.expense != nil || request.draft != nil) ? " La richiesta resta sul Watch." : "")
            return
        }
        guard let data = try? JSONEncoder().encode(request) else { return }
        let token = UUID()
        requestToken = token
        requestWasSave = request.confirmation != nil
        isSending = true
        message = nil
        WCSession.default.sendMessageData(data, replyHandler: { [weak self] data in
            Task { @MainActor [weak self] in self?.receiveReply(data, token: token, draftID: request.draft?.id, isRemote: request.expense != nil) }
        }, errorHandler: { [weak self] _ in
            Task { @MainActor [weak self] in self?.failed(token) }
        })
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(20))
            if self?.requestToken == token, self?.isSending == true { self?.failed(token) }
        }
    }
    private func failed(_ token: UUID) {
        guard requestToken == token else { return }
        isSending = false
        message = requestWasSave ? "Conferma non ricevuta. Riprova per verificare se la spesa è registrata." : "Invio non confermato. Riprova la stessa richiesta."
    }
    private func receiveReply(_ data: Data, token: UUID, draftID: UUID?, isRemote: Bool) {
        guard requestToken == token else { return }
        isSending = false
        guard data.count <= 65_536, let reply = try? JSONDecoder().decode(WatchReply.self, from: data) else {
            message = "Risposta non valida. Riprova."; return
        }
        switch reply.status {
        case .accepted:
            if pendingDraft?.id == draftID { UserDefaults.standard.removeObject(forKey: draftKey) }
            message = "Bozza ricevuta. Apri Forgia su iPhone per controllare budget, conto e categoria e salvarla."
        case .busy: message = "Completa prima la bozza già in attesa su iPhone."
        case .invalid, .unavailable:
            message = reply.message ?? "Controlla importo e descrizione e riprova."
        case .changed:
            if isRemote {
                remote.confirmationWasSent = false
                remote.quote = nil
                persistRemote()
            }
            message = reply.message ?? "Controlla importo e descrizione e riprova."
        case .preview:
            guard let quote = reply.quote, quote.input == remote.input else { return }
            remote.quote = quote
            persistRemote()
        case .saved:
            guard let result = reply.result else { return }
            remote = WatchRemoteState(savedID: result.transactionID)
            persistRemote()
            message = result.alreadyRecorded ? "La richiesta era già stata registrata. Nessuna spesa duplicata." : "Spesa registrata su iPhone."
        case .overview:
            if let snapshot = reply.overview, let data = try? JSONEncoder().encode(snapshot) { receiveOverview(data) }
        }
    }
    private func receiveOverview(_ data: Data) {
        guard data.count <= 65_536, let snapshot = try? JSONDecoder().decode(WatchOverview.self, from: data), snapshot.version == 1 else {
            overview = .redacted
            UserDefaults.standard.removeObject(forKey: snapshotKey)
            return
        }
        overview = snapshot
        UserDefaults.standard.set(data, forKey: snapshotKey)
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let data = session.receivedApplicationContext["overview"] as? Data
        Task { @MainActor [weak self] in
            if let data { self?.receiveOverview(data) }
            self?.refresh()
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        guard let data = applicationContext["overview"] as? Data else { return }
        Task { @MainActor [weak self] in self?.receiveOverview(data) }
    }
}
