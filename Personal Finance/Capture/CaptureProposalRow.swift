import SwiftUI
import FinanceCore

struct CaptureProposalRow: View {
    let capture: PendingCapture
    let conti: [Conto]
    let history: [FinanceTransaction]
    @State private var documentText = ""
    @State private var reading = false
    @State private var readingMessage: String?
    @AppStorage(CaptureBankDefaultsStorage.key) private var bankDefaultsData = Data()
    private var text: String { [capture.originalText, documentText].filter { !$0.isEmpty }.joined(separator: "\n") }
    private var suggestion: CaptureClassification {
        CaptureClassifier.suggest(destination: capture.destinationName, source: capture.sourceName,
            text: text, type: .expense, conti: conti, history: history,
            bankDefaults: CaptureBankDefaultsStorage.decode(bankDefaultsData), isBankNotification: capture.source == "notification")
    }
    private var conto: Conto? { conti.first { $0.id == suggestion.contoID } }
    private var book: Account? { conti.compactMap(\.account).first { $0.id == suggestion.bookID } }
    private var category: FinanceCore.Category? { book?.categories?.first { $0.id == suggestion.categoryID } }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
            if capture.document != nil { CaptureAttachmentPreview(capture: capture, compact: true) }
            VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(CaptureTextParser.merchant(in: text) ?? capture.filename ?? capture.sourceName).font(.headline).lineLimit(2)
                Spacer()
                if CaptureTextParser.money(in: text).count == 1, let money = CaptureTextParser.money(in: text).first {
                    if money.currency.isEmpty {
                        Text(NSDecimalNumber(decimal: money.amount).stringValue).font(.headline).monospacedDigit()
                    } else {
                        Text(money.amount, format: .currency(code: money.currency)).font(.headline).monospacedDigit().foregroundStyle(ForgiaPalette.accent)
                    }
                }
            }
            Text("Libro: \(book?.name ?? "Da scegliere") · Conto: \(conto?.name ?? "Da scegliere")")
                .font(.subheadline).foregroundStyle(.secondary)
            Label("Categoria: \(category?.name ?? "Da scegliere")", systemImage: category?.icon ?? "tag")
                .font(.subheadline).foregroundStyle(category == nil ? .secondary : .primary)
            if let reason = suggestion.categoryReason ?? suggestion.accountReason { Text(reason).font(.caption).foregroundStyle(.secondary) }
            if reading { ProgressView("Lettura documento…").font(.caption) }
            if let readingMessage { Label(readingMessage, systemImage: "text.magnifyingglass").font(.caption).foregroundStyle(ForgiaPalette.spending) }
            if capture.document != nil, CaptureTextParser.merchant(in: text) != nil {
                Label(capture.filename ?? "Allegato", systemImage: "paperclip")
                    .font(.caption).foregroundStyle(ForgiaPalette.mutedText).lineLimit(2)
            }
            }
            }
            HStack {
                Text(capture.sourceName)
                Spacer()
                Text(capture.createdAt, format: .dateTime.day().month().hour().minute())
            }.font(.caption).foregroundStyle(.secondary)
        }
        .foregroundStyle(Color.primary)
        .task(id: capture.id) {
            guard capture.document != nil else { return }
            reading = true
            defer { reading = false }
            do {
                let result = try await CaptureDocumentReader.read(capture)
                documentText = result.text
                if result.status == .failed {
                    readingMessage = "Lettura non riuscita · Originale conservato"
                } else if result.status == .empty {
                    readingMessage = "Nessun testo leggibile · Originale conservato"
                } else if CaptureTextParser.money(in: text).isEmpty && !ReceiptAmounts.candidates(in: text).contains(where: \.isPossibleTotal) {
                    readingMessage = "Nessun importo riconosciuto · Da compilare"
                }
            } catch {
                readingMessage = "Lettura non riuscita · Originale conservato"
            }
        }
    }
}
