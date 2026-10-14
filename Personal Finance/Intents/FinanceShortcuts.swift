import AppIntents
import FinanceCore
import Foundation
import SwiftData
import Observation

/// A request carries only a draft; intents never write financial movements.
enum FinanceShortcutRequest: Equatable, Sendable {
    case capture(CaptureShortcutDraft)
    case captureNotification(UUID)
    case watchExpense(WatchExpenseDraft)
    case widget(FinanceWidgetRoute)
    case today
    case planning
    case reminderPlanning
    case expense(amount: String, description: String)
    case income(amount: String, description: String)
}

/// Dock and Home Screen actions use the same protected draft delivery as Shortcuts.
enum FinanceIconQuickAction {
    static let newExpenseType = "cc.fbianco.finance.new-expense"

    @MainActor
    @discardableResult
    static func receive(_ type: String, inbox: FinanceShortcutInbox = .shared) -> Bool {
        guard type == newExpenseType else { return false }
        do {
            try inbox.submit(.expense(amount: "", description: ""))
            return true
        } catch {
            inbox.reportError("Completa la richiesta già aperta in Formi.")
            return false
        }
    }
}

@MainActor @Observable
final class FinanceShortcutInbox {
    static let shared = FinanceShortcutInbox()
    var errorMessage: String?
    func reportError(_ message: String) { errorMessage = message }
    private(set) var pending: FinanceShortcutRequest?

    func submit(_ request: FinanceShortcutRequest) throws {
        guard pending == nil || pending == request else { throw FinanceShortcutError.busy }
        pending = request
    }

    /// Called only by the unlocked, initialized main interface.
    func deliver(to state: AppStateManager, canAccessContent: Bool = true, accounts: [Account] = [], captureStore: ModelContainer? = nil) {
        guard canAccessContent, let request = pending,
              !state.showingQuickTransaction, !state.showingTransferSheet,
              !state.showingAccountSelection, !state.showingAccountCreation else { return }
        pending = nil
        switch request {
        case let .captureNotification(id):
            do {
                let store = try captureStore ?? CaptureStore.container()
                guard let capture = try CaptureStore.captures(ids: [id], in: store).first else {
                    errorMessage = "La proposta è già stata approvata o scartata su questo dispositivo."
                    return
                }
                state.presentQuickTransaction(type: capture.reviewType)
                state.captureShortcutDraft = CaptureShortcutDraft(id: id, amount: nil, note: nil, type: capture.reviewType)
            } catch {
                errorMessage = "Impossibile aprire la proposta. Riprova da Da approvare."
            }
        case let .capture(draft):
            state.presentQuickTransaction(type: draft.type)
            state.captureShortcutDraft = draft
        case let .watchExpense(draft):
            if let id = draft.bookID {
                guard let account = accounts.first(where: { $0.id == id && $0.isActive == true }) else {
                    WatchDraftMailbox.shared.delivered(draft.id)
                    errorMessage = "Il libro scelto sul Watch non è disponibile. Prepara di nuovo la spesa scegliendo un altro libro."
                    return
                }
                state.selectAccount(account)
            }
            guard let amount = draft.normalizedAmount else {
                WatchDraftMailbox.shared.delivered(draft.id)
                return
            }
            WatchDraftMailbox.shared.presented(draft.id)
            state.presentQuickTransaction()
            state.watchDraftID = draft.id
            state.quickTransactionPrefill = (amount, draft.note)
        case let .widget(route):
            if let id = route.bookID {
                guard let account = accounts.first(where: { $0.id == id && $0.isActive == true }) else {
                    errorMessage = "Il libro del widget non è disponibile. Aggiorna il widget o scegli un altro libro."
                    return
                }
                state.selectAccount(account)
            }
            switch route.destination {
            case .today: state.selectTab(.dashboard)
            case .planning: state.selectTab(.planning)
            case .analysis: state.selectTab(.analysis)
            case .expense: state.presentQuickTransaction()
            }
        case .today: state.selectTab(.dashboard)
        case .planning: state.selectTab(.planning)
        case .reminderPlanning:
            state.selectAllAccounts()
            state.selectTab(.planning)
        case let .expense(amount, description):
            state.presentQuickTransaction()
            state.quickTransactionPrefill = (amount, description)
        case let .income(amount, description):
            state.presentQuickTransaction(type: .income)
            state.quickTransactionPrefill = (amount, description)
        }
    }
}

enum FinanceShortcutError: Error, CustomLocalizedStringResourceConvertible {
    case invalidAmount, busy, missingCapture
    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .invalidAmount: "Inserisci un importo positivo, senza simboli di valuta o separatori delle migliaia."
        case .busy: "C’è già una richiesta in attesa. Apri Formi per completarla."
        case .missingCapture: "La proposta non è più disponibile su questo dispositivo. Potrebbe essere già stata approvata o scartata."
        }
    }
}

enum ShortcutAmount {
    static func normalized(_ text: String?) throws -> String {
        let value = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "" }
        guard value.count <= 29,
              value.range(of: #"^[0-9]+([.,][0-9]+)?$"#, options: .regularExpression) != nil,
              let amount = Decimal(string: value.replacingOccurrences(of: ",", with: ".")),
              amount > 0, !amount.isNaN else { throw FinanceShortcutError.invalidAmount }
        return value.replacingOccurrences(of: ".", with: ",")
    }
}

struct PrepareExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Prepara una spesa"
    static let description = IntentDescription("Prepara una spesa da controllare e salvare in Formi. Le notifiche bancarie restano in Da approvare in background, salvo attivare Apri per approvare. L’importo usa la valuta del libro selezionato; nessun movimento viene salvato automaticamente.")
    static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }

    @Parameter(title: "Importo nella valuta del libro") var amount: String?
    @Parameter(title: "Descrizione") var note: String?
    @Parameter(title: "Info transazione bancaria") var transaction: CaptureTransactionEntity?
    @Parameter(title: "Apri per approvare", default: false) var openForReview: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Prepara una spesa") {
            \.$transaction
            \.$amount
            \.$note
            \.$openForReview
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let request = try makeRequest()
        if try storeForBackgroundReview(request) { return .result() }
        if systemContext.currentMode != .foreground {
            guard systemContext.currentMode.canContinueInForeground else {
                throw needsToContinueInForegroundError("Apri Formi per controllare la proposta.")
            }
            try await continueInForeground(alwaysConfirm: false)
        }
        try FinanceShortcutInbox.shared.submit(request)
        return .result()
    }

    @MainActor
    @discardableResult
    func storeForBackgroundReview(_ request: FinanceShortcutRequest, in captureStore: ModelContainer? = nil) throws -> Bool {
        guard !openForReview, case let .capture(draft) = request else { return false }
        let store = try captureStore ?? CaptureStore.container()
        guard try !CaptureStore.captures(ids: [draft.id], in: store).isEmpty else {
            throw FinanceShortcutError.missingCapture
        }
        try CaptureStore.prepareForReview(id: draft.id, type: draft.type, amount: draft.amount, note: draft.note, in: store)
        return true
    }

    @MainActor func makeRequest(in captureStore: ModelContainer? = nil) throws -> FinanceShortcutRequest {
        let normalized = try ShortcutAmount.normalized(amount)
        if let transaction {
            let store = try captureStore ?? CaptureStore.container()
            guard try !CaptureStore.captures(ids: [transaction.id], in: store).isEmpty else {
                throw FinanceShortcutError.missingCapture
            }
            return .capture(CaptureShortcutDraft(id: transaction.id, amount: normalized.isEmpty ? nil : normalized, note: note))
        } else {
            return .expense(amount: normalized, description: note ?? "")
        }
    }
}

struct PrepareIncomeIntent: AppIntent {
    static let title: LocalizedStringResource = "Prepara un’entrata"
    static let description = IntentDescription("Prepara un’entrata da controllare e salvare in Formi. Le notifiche bancarie restano in Da approvare in background, salvo attivare Apri per approvare. Puoi passare il risultato di Acquisisci notifica bancaria, per esempio una notifica dello stipendio. Nessun movimento viene salvato automaticamente.")
    static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }

    @Parameter(title: "Importo nella valuta del libro") var amount: String?
    @Parameter(title: "Descrizione") var note: String?
    @Parameter(title: "Info transazione bancaria") var transaction: CaptureTransactionEntity?
    @Parameter(title: "Apri per approvare", default: false) var openForReview: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Prepara un’entrata") {
            \.$transaction
            \.$amount
            \.$note
            \.$openForReview
        }
    }

    @MainActor func perform() async throws -> some IntentResult {
        let request = try makeRequest()
        if try storeForBackgroundReview(request) { return .result() }
        if systemContext.currentMode != .foreground {
            guard systemContext.currentMode.canContinueInForeground else {
                throw needsToContinueInForegroundError("Apri Formi per controllare la proposta.")
            }
            try await continueInForeground(alwaysConfirm: false)
        }
        try FinanceShortcutInbox.shared.submit(request)
        return .result()
    }

    @MainActor
    @discardableResult
    func storeForBackgroundReview(_ request: FinanceShortcutRequest, in captureStore: ModelContainer? = nil) throws -> Bool {
        guard !openForReview, case let .capture(draft) = request else { return false }
        let store = try captureStore ?? CaptureStore.container()
        guard try !CaptureStore.captures(ids: [draft.id], in: store).isEmpty else {
            throw FinanceShortcutError.missingCapture
        }
        try CaptureStore.prepareForReview(id: draft.id, type: draft.type, amount: draft.amount, note: draft.note, in: store)
        return true
    }

    @MainActor func makeRequest(in captureStore: ModelContainer? = nil) throws -> FinanceShortcutRequest {
        let normalized = try ShortcutAmount.normalized(amount)
        if let transaction {
            let store = try captureStore ?? CaptureStore.container()
            guard try !CaptureStore.captures(ids: [transaction.id], in: store).isEmpty else {
                throw FinanceShortcutError.missingCapture
            }
            return .capture(CaptureShortcutDraft(id: transaction.id, amount: normalized.isEmpty ? nil : normalized, note: note, type: .income))
        }
        return .income(amount: normalized, description: note ?? "")
    }
}

struct OpenFinancialTodayIntent: AppIntent {
    static let title: LocalizedStringResource = "Apri il riepilogo di oggi"
    static var supportedModes: IntentModes { .foreground }
    @MainActor
    func perform() async throws -> some IntentResult {
        try FinanceShortcutInbox.shared.submit(.today)
        return .result()
    }
}

struct OpenFinancialPlanningIntent: AppIntent {
    static let title: LocalizedStringResource = "Apri budget e scadenze"
    static var supportedModes: IntentModes { .foreground }
    @MainActor
    func perform() async throws -> some IntentResult {
        try FinanceShortcutInbox.shared.submit(.planning)
        return .result()
    }
}

struct FinanceShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: PrepareExpenseIntent(), phrases: ["Prepara una spesa in \(.applicationName)"], shortTitle: "Nuova spesa", systemImageName: "plus.circle")
        AppShortcut(intent: PrepareIncomeIntent(), phrases: ["Prepara un’entrata in \(.applicationName)"], shortTitle: "Nuova entrata", systemImageName: "arrow.down.left.circle")
        AppShortcut(intent: OpenFinancialTodayIntent(), phrases: ["Apri il riepilogo in \(.applicationName)"], shortTitle: "Riepilogo di oggi", systemImageName: "house")
        AppShortcut(intent: OpenFinancialPlanningIntent(), phrases: ["Apri budget e scadenze in \(.applicationName)"], shortTitle: "Budget e scadenze", systemImageName: "calendar")
    }
}
