#if DEBUG
import SwiftUI
import SwiftData
import FinanceCore
import UniformTypeIdentifiers
import CoreGraphics
import CoreText

/// Isolated ledger for exercising the actual intake intent and system share sheet.
struct CaptureFixture: View {
    @State private var appState: AppStateManager
    private static let data: (container: ModelContainer, book: Account) = {
        let container = try! FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let book = Account(name: "Prova acquisizione", currency: "EUR")
        let conto = Conto(name: "Banca QA", type: .checking, initialBalance: 500)
        let category = FinanceCore.Category(name: "Alimentari")
        conto.account = book; category.account = book
        book.conti = [conto]; book.categories = [category]
        container.mainContext.insert(book)
        if ProcessInfo.processInfo.arguments.contains("UITEST_CAPTURE_CLASSIFICATION") {
            for _ in 0..<2 {
                let movement = FinanceTransaction(amount: 20, type: .expense, transactionDescription: "Esselunga QA")
                movement.setFromConto(conto); movement.setCategory(category)
                container.mainContext.insert(movement)
            }
        }
        try! container.mainContext.save()
        return (container, book)
    }()
    init() {
        let state = AppStateManager()
        state.selectAccount(Self.data.book)
        _appState = State(initialValue: state)
    }
    var body: some View {
        CaptureFixtureWorkspace(book: Self.data.book)
            .modelContainer(Self.data.container).environment(appState)
    }
}
private struct CaptureFixtureWorkspace: View {
    let book: Account
    @Query private var transactions: [FinanceTransaction]
    @State private var error: String?
    @State private var acquired = false
    @State private var automaticReview: PendingCapture?
    @State private var sharingPDF = false
    @State private var sharingBlankImage = false
    var body: some View {
        NavigationStack {
            List {
                Button("Prova notifica bancaria") {
                    Task { await acquire() }
                }.accessibilityIdentifier("capture-test-notification")
                if acquired { Text("Notifica acquisita").accessibilityIdentifier("capture-test-acquired") }
                ShareLink(item: "Fattura QA\nTotale EUR 18,50\nFornitore: Cartoleria QA") {
                    Text("Condividi fattura di prova")
                }.accessibilityIdentifier("capture-test-share")
                #if os(iOS)
                Button("Condividi PDF di prova") { sharingPDF = true }
                    .accessibilityIdentifier("capture-test-share-pdf")
                Button("Condividi immagine senza testo") { sharingBlankImage = true }
                    .accessibilityIdentifier("capture-test-share-blank-image")
                #endif
                CaptureInboxEntry()
                if ProcessInfo.processInfo.arguments.contains("UITEST_CAPTURE_PAGINATION") {
                    Button("Pulisci paginazione QA") {
                        do { try CapturePaginationSample.clear() } catch { self.error = error.localizedDescription }
                    }.accessibilityIdentifier("capture-test-clear-pagination")
                }
                ForEach(transactions) { item in
                    Text("Registrato: \(item.amount?.description ?? "-")").accessibilityIdentifier("capture-test-recorded")
                }
                ForEach(book.activeConti) { conto in Text("Saldo: \(conto.balance.description)").accessibilityIdentifier("capture-test-balance") }
                if let error { Text(error) }
            }.navigationTitle("Prova acquisizione")
            .navigationDestination(isPresented: Binding(get: { automaticReview != nil }, set: { if !$0 { automaticReview = nil } })) {
                if let automaticReview { CaptureReviewView(capture: automaticReview, onFinish: {}) }
            }
            #if os(iOS)
            .sheet(isPresented: $sharingPDF) { CapturePDFShareSheet(url: CapturePDFSample.url) }
            .sheet(isPresented: $sharingBlankImage) { CapturePDFShareSheet(url: CaptureBlankImage.url) }
            #endif
            .task {
                if ProcessInfo.processInfo.arguments.contains("UITEST_CAPTURE_PAGINATION") {
                    do { try CapturePaginationSample.seed() } catch { self.error = error.localizedDescription }
                }
                if ProcessInfo.processInfo.arguments.contains("UITEST_CAPTURE_AUTO") {
                    await acquire()
                    automaticReview = try? CaptureStore.pending(in: CaptureStore.container()).first { $0.originalText == "Pagamento 24,90 EUR presso Esselunga QA" }
                }
            }
        }
    }
    private func acquire() async {
        do {
            let intent = CaptureBankNotificationIntent()
            intent.text = "Pagamento 24,90 EUR presso Esselunga QA"
            intent.bank = "Banca QA"; intent.destination = "Banca QA"
            if ProcessInfo.processInfo.arguments.contains("UITEST_CAPTURE_ROUTING") {
                intent.bank = "Instradamento QA"; intent.destination = ""
            }
            _ = try await intent.perform()
            acquired = true
        } catch { self.error = error.localizedDescription }
    }
}
@MainActor private enum CapturePaginationSample {
    static func clear() throws {
        let context = ModelContext(try CaptureStore.container())
        for capture in try context.fetch(FetchDescriptor<PendingCapture>(predicate: #Predicate { $0.sourceName == "Paginazione QA" })) {
            context.delete(capture)
        }
        try context.save()
    }
    static func seed() throws {
        try clear()
        let context = ModelContext(try CaptureStore.container())
        let now = Date()
        for index in 1...72 {
            let label = String(format: "Pagina QA %03d", index)
            let capture = PendingCapture(source: "notification", sourceName: "Paginazione QA", text: "Pagamento EUR 1,00 presso \(label)")
            capture.createdAt = now.addingTimeInterval(-Double(index) / 1000)
            context.insert(capture)
        }
        try context.save()
    }
}
private struct CapturePDFSample {
    static let url: URL = {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 400, height: 300)
        let consumer = CGDataConsumer(data: data)!
        let context = CGContext(consumer: consumer, mediaBox: &box, nil)!
        context.beginPDFPage(nil)
        context.textPosition = CGPoint(x: 30, y: 220)
        let font = CTFontCreateWithName("Helvetica" as CFString, 16, nil)
        let text = NSAttributedString(string: "Fattura QA - Totale EUR 18,50", attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        CTLineDraw(CTLineCreateWithAttributedString(text), context)
        context.endPDFPage(); context.closePDF()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Fattura-QA.pdf")
        try! (data as Data).write(to: url, options: .atomic)
        return url
    }()
}
#if os(iOS)
private enum CaptureBlankImage {
    static let url: URL = {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 300)).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Immagine-senza-testo.png")
        try! image.pngData()!.write(to: url, options: .atomic)
        return url
    }()
}
private struct CapturePDFShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#endif
#endif
