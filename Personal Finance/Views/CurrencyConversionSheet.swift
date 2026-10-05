import SwiftUI
import FinanceCore

struct ForeignAmountDraft: Equatable {
    let originalAmount: Decimal
    let originalCurrency: String
    let targetCurrency: String
    let rate: Decimal
    let rateDay: String?
    let source: String
    var converted: Decimal? { try? CurrencyConversion.convert(originalAmount, rate: rate, currency: targetCurrency) }
    func apply(to transaction: FinanceTransaction) {
        transaction.originalAmount = originalAmount
        transaction.originalCurrency = originalCurrency
        transaction.exchangeRate = rate
        transaction.exchangeRateDate = rateDay
        transaction.exchangeRateSource = source
    }
    static func load(_ transaction: FinanceTransaction) -> Self? {
        guard let original = transaction.originalAmount, let currency = transaction.originalCurrency, let rate = transaction.exchangeRate else { return nil }
        return Self(originalAmount: original, originalCurrency: currency,
                    targetCurrency: transaction.fromConto?.account?.currency ?? transaction.toConto?.account?.currency ?? "EUR",
                    rate: rate, rateDay: transaction.exchangeRateDate, source: transaction.exchangeRateSource ?? "Manuale")
    }
    static func clear(_ transaction: FinanceTransaction) {
        transaction.originalAmount = nil; transaction.originalCurrency = nil; transaction.exchangeRate = nil
        transaction.exchangeRateDate = nil; transaction.exchangeRateSource = nil
    }
}

/// Keeps the provenance attached to the exact currency pair and rate that supplied it.
struct ForeignAmountEditor {
    let targetCurrency: String
    var originalCurrency: String
    var originalAmount: String
    var rateText: String
    private var rateReference: ForeignAmountDraft?

    init(targetCurrency: String, existing: ForeignAmountDraft? = nil) {
        self.targetCurrency = targetCurrency
        let existing = existing.flatMap { $0.targetCurrency == targetCurrency ? $0 : nil }
        originalCurrency = existing?.originalCurrency ?? (targetCurrency == "USD" ? "EUR" : "USD")
        originalAmount = existing.map { NSDecimalNumber(decimal: $0.originalAmount).stringValue } ?? ""
        rateText = existing.map { NSDecimalNumber(decimal: $0.rate).stringValue } ?? ""
        rateReference = existing
    }

    private func parse(_ text: String) -> Decimal? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.range(of: #"^[0-9]+(?:[.,][0-9]+)?$"#, options: .regularExpression) != nil else { return nil }
        return Decimal(string: value.replacingOccurrences(of: ",", with: "."))
    }

    var draft: ForeignAmountDraft? {
        guard originalCurrency != targetCurrency,
              let amount = parse(originalAmount), let rate = parse(rateText),
              amount > 0, rate > 0 else { return nil }
        let reference = rateReference.flatMap {
            $0.originalCurrency == originalCurrency && $0.rate == rate ? $0 : nil
        }
        return ForeignAmountDraft(originalAmount: amount, originalCurrency: originalCurrency,
                                  targetCurrency: targetCurrency, rate: rate,
                                  rateDay: reference?.rateDay, source: reference?.source ?? "Manuale")
    }

    mutating func clearRate() {
        rateText = ""
        rateReference = nil
    }

    mutating func apply(_ snapshot: CurrencyRateSnapshot) throws {
        let rate = try snapshot.rate(from: originalCurrency, to: targetCurrency)
        rateText = NSDecimalNumber(decimal: rate).stringValue
        rateReference = ForeignAmountDraft(originalAmount: 1, originalCurrency: originalCurrency,
                                          targetCurrency: targetCurrency, rate: rate,
                                          rateDay: snapshot.day, source: "BCE")
    }
}

struct CurrencyConversionSheet: View {
    let targetCurrency: String
    let transactionDate: Date
    let onApply: (ForeignAmountDraft) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var editor: ForeignAmountEditor
    @State private var loading = false
    @State private var loadTask: Task<Void, Never>?
    @State private var message: String?
    @State private var requestID: UUID?

    init(targetCurrency: String, transactionDate: Date, existing: ForeignAmountDraft? = nil,
         onApply: @escaping (ForeignAmountDraft) -> Void) {
        self.targetCurrency = targetCurrency
        self.transactionDate = transactionDate
        self.onApply = onApply
        _editor = State(initialValue: ForeignAmountEditor(targetCurrency: targetCurrency, existing: existing))
    }

    private var draft: ForeignAmountDraft? { editor.draft }
    var body: some View {
        NavigationStack {
            Form {
                Section("Importo originale") {
                    Picker("Valuta", selection: $editor.originalCurrency) {
                        ForEach(Locale.commonISOCurrencyCodes.filter { $0 != targetCurrency }.sorted(), id: \.self) { code in
                            Text("\(code) · \(Locale.current.localizedString(forCurrencyCode: code) ?? code)").tag(code)
                        }
                    }
                    TextField("Importo in valuta estera", text: $editor.originalAmount)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                }
                Section("Cambio applicato") {
                    Text("1 \(editor.originalCurrency) = … \(targetCurrency)")
                    TextField("Tasso di cambio", text: $editor.rateText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Button("Scarica tasso BCE") {
                        let id = UUID()
                        requestID = id
                        loadTask = Task { await loadRate(id: id) }
                    }
                        .disabled(loading)
                    if loading { ProgressView() }
                    if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
                    if let draft, let converted = draft.converted {
                        Text(converted, format: .currency(code: targetCurrency)).font(.title2.bold())
                        Text(draft.rateDay.map { "Tasso \(draft.source) del \($0)" } ?? "Tasso inserito manualmente")
                            .font(.caption)
                    }
                }
                Section {
                    Text("Il tasso BCE è indicativo e non comprende commissioni. Per riconciliare il saldo usa il cambio effettivamente applicato dalla banca. Il tasso scelto resterà fissato nel movimento.")
                    Link("Fonte: Banca Centrale Europea", destination: URL(string: "https://www.ecb.europa.eu/stats/policy_and_exchange_rates/euro_reference_exchange_rates/html/index.en.html")!)
                }.font(.caption)
            }
            .navigationTitle("Valuta estera")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Usa importo") { if let draft, draft.converted != nil { onApply(draft); dismiss() } }
                        .disabled(draft?.converted == nil || loading)
                }
            }
            .onDisappear { cancelRequest() }
            .onChange(of: editor.originalCurrency) { _, _ in
                cancelRequest()
                editor.clearRate()
                message = nil
            }
        }
    }

    private func cancelRequest() {
        loadTask?.cancel()
        loadTask = nil
        requestID = nil
        loading = false
    }

    private func loadRate(id: UUID) async {
        guard requestID == id, !Task.isCancelled else { return }
        loading = true
        message = nil
        defer { if requestID == id { loading = false } }
        let requestedCurrency = editor.originalCurrency
        do {
            var request = URLRequest(url: URL(string: "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-hist-90d.xml")!)
            request.timeoutInterval = 20
            let (data, response) = try await URLSession.shared.data(for: request)
            guard requestID == id, !Task.isCancelled, requestedCurrency == editor.originalCurrency else { return }
            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else { throw CurrencyConversion.Failure.invalidFeed }
            let snapshots = try CurrencyConversion.parseECB(data)
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            let day = formatter.string(from: transactionDate)
            guard let snapshot = snapshots.first(where: { $0.day <= day }) else {
                message = "Nessun tasso disponibile per questa data negli ultimi 90 giorni. Inserisci il tasso manualmente."; return
            }
            try editor.apply(snapshot)
        } catch is CancellationError {
        } catch {
            guard requestID == id, !Task.isCancelled else { return }
            message = "Cambio automatico non disponibile. Puoi inserire il tasso manualmente."
        }
    }
}
