#if os(iOS)
import Foundation
import WatchConnectivity
import SwiftData
import FinanceCore

@MainActor
final class WatchPhoneBridge: NSObject, WCSessionDelegate {
    static let shared = WatchPhoneBridge()
    static let preferenceKey = "watch.showFinancialData"
    private var overview = WatchOverview.redacted
    private var started = false

    func start() {
        guard !started, WCSession.isSupported() else { return }
        started = true
        WCSession.default.delegate = self
        WCSession.default.activate()
        flushDraft()
    }
    func flushDraft() {
        guard FinanceShortcutInbox.shared.pending == nil, let draft = WatchDraftMailbox.shared.awaitingPresentation else { return }
        try? FinanceShortcutInbox.shared.submit(.watchExpense(draft))
    }
    func refresh(container: ModelContainer, protected: Bool) {
        guard !protected, UserDefaults.standard.bool(forKey: Self.preferenceKey) else { redact(); return }
        do {
            let context = ModelContext(container)
            let accounts = try context.fetch(FetchDescriptor<Account>())
            let snapshot = try FinanceWidgetBuilder.build(
                accounts: accounts, budgets: context.fetch(FetchDescriptor<Budget>()),
                transactions: context.fetch(FetchDescriptor<FinanceTransaction>()),
                resolutions: context.fetch(FetchDescriptor<RecurrenceResolution>()))
            let week = Date().addingTimeInterval(7 * 86400)
            overview = WatchOverview(generatedAt: snapshot.generatedAt, validUntil: min(snapshot.validUntil, Date().addingTimeInterval(3600)),
                books: snapshot.books.map { book in
                    WatchBook(id: book.id, name: book.name, currency: book.currency,
                              monthSpent: book.monthSpent, budgetName: book.budget?.name,
                              budgetRemaining: book.budget?.remaining,
                              upcomingCount: book.occurrenceDates.filter { $0 <= week }.count,
                              conti: accounts.first(where: { $0.id == book.id })?.activeConti.map { WatchOption(id: $0.id, name: $0.name ?? "Conto") },
                              categories: accounts.first(where: { $0.id == book.id })?.categories?.filter { $0.isActive == true }.map { WatchOption(id: $0.id, name: $0.name ?? "Categoria") })
                }, hidden: snapshot.state != .ready)
        } catch { overview = .redacted }
        publish()
    }
    func redact() { overview = .redacted; publish() }
    private func publish() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              WCSession.default.isPaired, WCSession.default.isWatchAppInstalled,
              let data = try? JSONEncoder().encode(overview) else { return }
        try? WCSession.default.updateApplicationContext(["overview": data])
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.publish() }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.publish() }
    }
    private func handleExpense(_ input: RemoteExpenseInput, confirmation: RemoteExpenseQuote?) -> WatchReply {
        guard UserDefaults.standard.bool(forKey: Self.preferenceKey),
              !UserDefaults.standard.bool(forKey: AppLock.preferenceKey),
              let container = DataStorageManager.shared.currentContainer else {
            return WatchReply(status: .unavailable, overview: nil, message: "Apri Forgia su iPhone. Il salvataggio dal Watch richiede il riepilogo attivo e Forgia senza blocco.")
        }
        do {
            if let confirmation {
                let result = try RemoteExpenseService.save(input, confirmation: confirmation, container: container)
                refresh(container: container, protected: false)
                return WatchReply(status: .saved, overview: nil, result: result)
            }
            return WatchReply(status: .preview, overview: nil,
                              quote: try RemoteExpenseService.preview(input, container: container))
        } catch RemoteExpenseService.Failure.confirmationChanged {
            return WatchReply(status: .changed, overview: nil, message: "I budget sono cambiati. Controlla di nuovo prima di salvare.")
        } catch RemoteExpenseService.Failure.confirmationExpired {
            return WatchReply(status: .changed, overview: nil, message: "Il riepilogo è scaduto. Controlla di nuovo i budget.")
        } catch RemoteExpenseService.Failure.invalidSelection {
            return WatchReply(status: .changed, overview: nil, message: "Conto o categoria non più disponibili. Aggiorna il riepilogo.")
        } catch RemoteExpenseService.Failure.currencyChanged {
            return WatchReply(status: .changed, overview: nil, message: "La valuta del libro è cambiata. Aggiorna il riepilogo.")
        } catch {
            return WatchReply(status: .invalid, overview: nil, message: "Registrazione non confermata. Verifica importo, valuta, conto e categoria su iPhone.")
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data, replyHandler: @escaping (Data) -> Void) {
        Task { @MainActor in
            let reply: WatchReply
            if messageData.count <= 65_536,
               let request = try? JSONDecoder().decode(WatchRequest.self, from: messageData), request.version == 1 {
                if let expense = request.expense {
                    reply = self.handleExpense(expense, confirmation: request.confirmation)
                } else if let draft = request.draft {
                    reply = WatchReply(status: WatchDraftMailbox.shared.receive(draft), overview: nil)
                    self.flushDraft()
                } else {
                    // Re-check privacy before every response, even before views mount.
                    if UserDefaults.standard.bool(forKey: AppLock.preferenceKey) || !UserDefaults.standard.bool(forKey: Self.preferenceKey) {
                        self.overview = .redacted
                    }
                    reply = WatchReply(status: .overview, overview: self.overview)
                }
            } else { reply = WatchReply(status: .invalid, overview: nil) }
            replyHandler((try? JSONEncoder().encode(reply)) ?? Data())
        }
    }
}
#endif
