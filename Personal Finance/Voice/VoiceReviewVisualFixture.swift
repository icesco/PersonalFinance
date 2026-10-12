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

#if DEBUG
/// The dictation sheet while listening, driven by a synthetic voice level, to inspect the glow.
struct VoiceDictationVisualFixture: View {
    @State private var meter = VoiceAudioMeter()
    @State private var presented = false
    @State private var text = "Ieri sera ho speso 25 euro di sushi e stamattina 2 euro di caffè"

    var body: some View {
        ForgiaPalette.canvas.ignoresSafeArea()
            .sheet(isPresented: $presented) {
                VoiceDictationSurface(text: $text, meter: meter, recording: true, starting: false,
                                      finishing: false, processing: false,
                                      onToggleRecording: {}, onPrepare: {}, onClose: {})
                    .environment(\.locale, Locale(identifier: "it_IT"))
                    // Same bottom sheet as VoiceTransactionView while dictating.
                    .presentationDetents([.height(480)])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(28)
            }
            .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("UITEST_VOICE_DICTATION_DARK") ? .dark : .light)
            .task {
                presented = true
                // A speech-like envelope: syllables over a slower phrase rhythm.
                var t = 0.0
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(50))
                    t += 0.05
                    let phrase = 0.5 + 0.5 * sin(t * 1.3)
                    let syllable = 0.5 + 0.5 * sin(t * 9.0)
                    meter.level = min(1, 0.15 + phrase * 0.55 + syllable * 0.3 * phrase)
                }
            }
    }
}
#endif
