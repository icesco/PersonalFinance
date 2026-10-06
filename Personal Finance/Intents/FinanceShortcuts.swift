import AppIntents
import FinanceCore
import Foundation
import Observation

/// A request carries only a draft; intents never write financial movements.
enum FinanceShortcutRequest: Equatable, Sendable {
    case watchExpense(WatchExpenseDraft)
    case widget(FinanceWidgetRoute)
    case today
    case planning
    case reminderPlanning
    case expense(amount: String, description: String)
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
    func deliver(to state: AppStateManager, canAccessContent: Bool = true, accounts: [Account] = []) {
        guard canAccessContent, let request = pending,
              !state.showingQuickTransaction, !state.showingTransferSheet,
              !state.showingAccountSelection, !state.showingAccountCreation else { return }
        pending = nil
        switch request {
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
        }
    }
}

enum FinanceShortcutError: Error, CustomLocalizedStringResourceConvertible {
    case invalidAmount, busy
    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .invalidAmount: "Inserisci un importo positivo, senza simboli di valuta o separatori delle migliaia."
        case .busy: "C’è già una richiesta in attesa. Apri Forgia per completarla."
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
    static let description = IntentDescription("Apre una spesa da controllare e salvare in Forgia. L’importo usa la valuta del libro selezionato; nessun movimento viene salvato automaticamente.")
    static var supportedModes: IntentModes { .foreground }

    @Parameter(title: "Importo nella valuta del libro") var amount: String?
    @Parameter(title: "Descrizione") var note: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Prepara una spesa") {
            \.$amount
            \.$note
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let normalized = try ShortcutAmount.normalized(amount)
        try FinanceShortcutInbox.shared.submit(.expense(amount: normalized, description: note ?? ""))
        return .result()
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
        AppShortcut(intent: OpenFinancialTodayIntent(), phrases: ["Apri il riepilogo in \(.applicationName)"], shortTitle: "Riepilogo di oggi", systemImageName: "house")
        AppShortcut(intent: OpenFinancialPlanningIntent(), phrases: ["Apri budget e scadenze in \(.applicationName)"], shortTitle: "Budget e scadenze", systemImageName: "calendar")
    }
}
