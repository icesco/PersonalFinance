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
    private let reader = WatchOverviewReader()
    private var refreshTask: Task<Void, Never>?

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
        refreshTask?.cancel()
        refreshTask = Task { [weak self, reader] in
            do {
                try await Task.sleep(for: .milliseconds(350))
                let value = try await reader.load(container: container)
                try Task.checkCancellation()
                guard let self else { return }
                guard !UserDefaults.standard.bool(forKey: AppLock.preferenceKey),
                      UserDefaults.standard.bool(forKey: Self.preferenceKey) else { self.redact(); return }
                self.overview = value
                self.publish()
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                self?.overview = .redacted
                self?.publish()
            }
        }
    }
    func redact() {
        refreshTask?.cancel()
        overview = .redacted
        publish()
    }
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
            return WatchReply(status: .unavailable, overview: nil, message: "Apri Formi su iPhone. Il salvataggio dal Watch richiede il riepilogo attivo e Formi senza blocco.")
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

private actor WatchOverviewReader {
    func load(container: ModelContainer) async throws -> WatchOverview {
        try Task.checkCancellation()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let accounts = try context.fetch(FetchDescriptor<Account>())
        let transactions = try context.fetch(FetchDescriptor<FinanceTransaction>())
        let now = Date()
        let conti = accounts.flatMap { $0.conti ?? [] }
        FinanceDataChangeCenter.shared.rememberCategories(container: container, categories: transactions.compactMap(\.category))
        let ledger = try await LedgerCalculationCoordinator.shared.prepare(container: container,
            accounts: conti.map(LedgerCacheAccount.init), transactions: transactions.map(TransactionSnapshot.init(from:)), now: now)
        let snapshot = try FinanceWidgetBuilder.build(
            accounts: accounts, budgets: context.fetch(FetchDescriptor<Budget>()),
            transactions: transactions,
            resolutions: context.fetch(FetchDescriptor<RecurrenceResolution>()), now: now,
            ledgerSnapshots: ledger.snapshots)
        let week = Date().addingTimeInterval(7 * 86400)
        let overview = WatchOverview(generatedAt: snapshot.generatedAt, validUntil: min(snapshot.validUntil, Date().addingTimeInterval(3600)),
            books: snapshot.books.map { book in
                WatchBook(id: book.id, name: book.name, currency: book.currency,
                          monthSpent: book.monthSpent, budgetName: book.budget?.name,
                          budgetRemaining: book.budget?.remaining,
                          upcomingCount: book.occurrenceDates.filter { $0 <= week }.count,
                          conti: accounts.first(where: { $0.id == book.id })?.activeConti.map { WatchOption(id: $0.id, name: $0.name ?? "Conto") },
                          categories: accounts.first(where: { $0.id == book.id }).map(Self.expenseCategories))
            }, hidden: snapshot.state != .ready)
        try Task.checkCancellation()
        LedgerCache.apply(ledger, to: conti)
        do { try FinanceDataChangeCenter.shared.saveCache(context: context) }
        catch { context.rollback() }
        return overview
    }

    /// Expense categories in tree order; subcategories carry their macro category's name.
    static func expenseCategories(of book: Account) -> [WatchOption] {
        let hierarchy = CategoryHierarchy(categories: book.categories ?? [], kind: .expense)
        return hierarchy.roots.flatMap { [$0] + hierarchy.children(of: $0) }
            .map { WatchOption(id: $0.id, name: hierarchy.path(of: $0)) }
    }
}
#endif
