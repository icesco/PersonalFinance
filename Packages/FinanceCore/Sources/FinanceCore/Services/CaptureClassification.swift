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
        else if !destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let matches = scoped.filter { normalize($0.name ?? "") == normalize(destination) }
            if matches.count == 1 { chosen = matches[0]; result.accountReason = "Conto indicato dalla fonte" }
            // An explicit but ambiguous/missing destination must never be replaced by a guess.
        } else if isBankNotification, ["wallet", "apple wallet"].contains(normalize(source)),
                  let matches = walletAccounts(text: text, conti: scoped) {
            if matches.count == 1 {
                chosen = matches[0]
                result.accountReason = "Carta riconosciuta nella notifica Wallet"
            } else {
                result.accountReason = matches.isEmpty
                    ? "Carta Wallet non associata a un conto attivo · Scegli una destinazione"
                    : "Più conti corrispondono alla carta Wallet · Scegli una destinazione"
            }
        } else if selectedBookID != nil, scoped.count == 1 {
            chosen = scoped[0]; result.accountReason = "Unico conto attivo del libro selezionato"
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
        let categories = SharedContoCategories.available(for: chosen, in: chosen?.account?.categories ?? []).filter { $0.fits(type) }
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
    /// Wallet is a container for several cards. Match its card evidence before a generic app default or merchant history.
    private static func walletAccounts(text: String, conti: [Conto]) -> [Conto]? {
        let routingText = text.components(separatedBy: .newlines).map {
            $0.replacingOccurrences(of: #"\b(presso|at|merchant|esercente|beneficiario|fornitore)\b.*$"#,
                with: "", options: [.regularExpression, .caseInsensitive])
        }.joined(separator: "\n")
        let signal = " " + cardName(routingText) + " "
        let candidates = conti.filter { $0.type == .credit || $0.type == .checking }
        let named = candidates.compactMap { conto -> (Conto, String)? in
            let name = cardName(conto.name ?? "")
            let genericNames: Set<String> = ["banca", "conto", "conto corrente", "carta", "carta di credito", "carta di debito",
                "credito", "debito", "personale", "principale", "wallet", "apple wallet", "credit card", "debit card"]
            guard name.count >= 4, !genericNames.contains(name), signal.contains(" " + name + " ") else { return nil }
            return (conto, name)
        }
        if !named.isEmpty {
            return named.filter { candidate in
                !named.contains { other in
                    other.1 != candidate.1 && (" " + other.1 + " ").contains(" " + candidate.1 + " ")
                }
            }.map(\.0)
        }
        if signal.contains(" american express ") {
            return candidates.filter { (" " + cardName($0.name ?? "") + " ").contains(" american express ") }
        }
        return nil
    }
    private static func cardName(_ text: String) -> String {
        var name = normalize(text).replacingOccurrences(of: #"\bamex\b"#, with: "american express", options: .regularExpression)
        for prefix in ["carta di credito ", "carta di debito ", "credit card ", "debit card ", "carta ", "card "] {
            if name.hasPrefix(prefix) { name.removeFirst(prefix.count); break }
        }
        return name
    }
    nonisolated public static func bankKey(_ text: String) -> String { normalize(text) }
    nonisolated private static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "it_IT"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
}
