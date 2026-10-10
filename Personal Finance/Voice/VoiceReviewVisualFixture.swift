#if DEBUG
import SwiftUI
import SwiftData
import FinanceCore

struct VoiceReviewVisualFixture: View {
    @State private var state = AppStateManager(persistsSelection: false)
    @State private var review: Review?
    private struct Review: Identifiable {
        let id = UUID()
        let drafts: [VoiceTransactionDraft]
    }
    private static let container = try! FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)

    var body: some View {
        ForgiaPalette.canvas.ignoresSafeArea()
            .sheet(item: $review) { review in
                VoiceTransactionView(previewDrafts: review.drafts,
                    previewText: "Ho speso 3 euro al bar e 5 euro al supermercato.")
                    .modelContainer(Self.container)
                    .environment(state)
                    .environment(\.locale, Locale(identifier: "it_IT"))
                    .environment(\.dynamicTypeSize, ProcessInfo.processInfo.arguments.contains("UITEST_VOICE_REVIEW_LARGE_TEXT") ? .accessibility3 : .large)
            }
            .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("UITEST_VOICE_REVIEW_DARK") ? .dark : .light)
            .task {
                guard review == nil else { return }
                let book = Account(name: "Libro di prova")
                let conto = Conto(name: "Contanti", type: .cash)
                conto.account = book
                book.conti = [conto]
                Self.container.mainContext.insert(book)
                try? Self.container.mainContext.save()
                state.selectAccount(book)
                let now = Date()
                let drafts = [
                    VoiceTransactionDraft(amount: "3", currency: "EUR", type: .expense,
                                          note: "Bar", date: now, contoID: conto.id),
                    VoiceTransactionDraft(amount: "5", currency: "EUR", type: .expense,
                                          note: "Supermercato", date: now, contoID: conto.id)
                ]
                review = Review(drafts: drafts)
            }
    }
}
#endif
