import Foundation

public struct CaptureBankDefault: Codable, Identifiable, Sendable {
    public var bank: String
    public var bookID: UUID
    public var contoID: UUID
    public var id: String { CaptureClassifier.bankKey(bank) }
    public init(bank: String, bookID: UUID, contoID: UUID) {
        self.bank = bank; self.bookID = bookID; self.contoID = contoID
    }
}

/// Suggestions refer exclusively to existing, active ledger objects. Ambiguity stays visible.
public struct CaptureClassification {
    public var bookID: UUID?
    public var contoID: UUID?
    public var categoryID: UUID?
    public var accountReason: String?
    public var categoryReason: String?
}

@MainActor public enum CaptureClassifier {
    public static func suggest(destination: String, source: String, text: String, type: TransactionType,
                               conti: [Conto], history: [Transaction], selectedBookID: UUID? = nil,
                               selectedContoID: UUID? = nil, bankDefaults: [CaptureBankDefault] = [],
                               isBankNotification: Bool = false) -> CaptureClassification {
        let active = conti.filter { $0.isActive == true && $0.account?.isActive == true }
        let scoped = active.filter { selectedBookID == nil || $0.account?.id == selectedBookID }
        var result = CaptureClassification(bookID: selectedBookID)
        let merchant = CaptureTextParser.merchant(in: text).map(normalize)
        let matchingHistory = history.filter {
            guard $0.type == type, let merchant, !merchant.isEmpty else { return false }
            return normalize($0.transactionDescription ?? "") == merchant
        }
        var chosen: Conto?
        if let selectedContoID {
            chosen = scoped.first { $0.id == selectedContoID }
            // Keep the explanation when an automatically chosen destination is
            // re-evaluated after field changes; manual overrides have no such label.
            let automatic = suggest(destination: destination, source: source, text: text, type: type,
                conti: conti, history: history, bankDefaults: bankDefaults, isBankNotification: isBankNotification)
            if chosen != nil, automatic.contoID == selectedContoID { result.accountReason = automatic.accountReason }
        }
        else if selectedBookID != nil, scoped.count == 1 {
            chosen = scoped[0]; result.accountReason = "Unico conto attivo del libro selezionato"
        }
        else if !destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let matches = scoped.filter { normalize($0.name ?? "") == normalize(destination) }
            if matches.count == 1 { chosen = matches[0]; result.accountReason = "Conto indicato dalla fonte" }
            // An explicit but ambiguous/missing destination must never be replaced by a guess.
        } else if isBankNotification, let configured = bankDefaults.first(where: { bankKey($0.bank) == bankKey(source) }) {
            chosen = scoped.first { $0.id == configured.contoID && $0.account?.id == configured.bookID }
            result.accountReason = chosen == nil ? "Conto predefinito non disponibile · Scegli una destinazione" : "Conto predefinito per \(configured.bank)"
        } else {
            let sourceMatches = scoped.filter { !normalize(source).isEmpty && normalize($0.name ?? "") == normalize(source) }
            if sourceMatches.count == 1 { chosen = sourceMatches[0]; result.accountReason = "Corrispondenza con la banca di origine" }
            else if sourceMatches.isEmpty {
                let historicalIDs = matchingHistory.compactMap { type == .expense ? ($0.fromConto?.id ?? $0.fromContoId) : ($0.toConto?.id ?? $0.toContoId) }
                let ids = Set(historicalIDs)
                if matchingHistory.count >= 2, historicalIDs.count == matchingHistory.count, ids.count == 1, let id = ids.first,
                   let account = scoped.first(where: { $0.id == id }) {
                    chosen = account; result.accountReason = "Conto usato nei movimenti dello stesso esercente"
                }
            }
            if chosen == nil, active.count == 1, scoped.count == 1 {
                chosen = active[0]; result.accountReason = "Unico libro e conto disponibili"
            }
        }
        if let chosen { result.contoID = chosen.id; result.bookID = chosen.account?.id }
        guard let bookID = result.bookID else { return result }
        let categories = (active.first { $0.account?.id == bookID }?.account?.categories ?? []).filter { $0.isActive == true && $0.fits(type) }
        let bookHistory = matchingHistory.filter {
            let account = type == .expense ? $0.fromConto?.account : $0.toConto?.account
            return account?.id == bookID
        }
        let categoryIDs = Set(bookHistory.compactMap { $0.category?.id })
        if bookHistory.count >= 2, bookHistory.allSatisfy({ $0.category != nil }), categoryIDs.count == 1,
           let id = categoryIDs.first, categories.contains(where: { $0.id == id }) {
            result.categoryID = id
            result.categoryReason = "Categoria usata per questo esercente"
        } else if bookHistory.count < 2 {
            // Match the user's category names as whole phrases, never arbitrary AI-created labels.
            let normalizedText = " " + normalize(text) + " "
            let matches = categories.filter {
                let name = normalize($0.name ?? "")
                return name.count >= 4 && normalizedText.contains(" " + name + " ")
            }
            if matches.count == 1 { result.categoryID = matches[0].id; result.categoryReason = "Categoria riconosciuta nel testo" }
        }
        return result
    }
    nonisolated public static func bankKey(_ text: String) -> String { normalize(text) }
    nonisolated private static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "it_IT"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
}
