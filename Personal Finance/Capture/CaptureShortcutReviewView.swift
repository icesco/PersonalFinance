import SwiftUI
import SwiftData
import FinanceCore

struct CaptureShortcutReviewView: View {
    let draft: CaptureShortcutDraft
    @Environment(AppStateManager.self) private var appState
    @State private var store: ModelContainer?
    @State private var capture: PendingCapture?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if let capture {
                    CaptureReviewView(capture: capture, onFinish: { appState.dismissQuickTransaction() },
                                      amountOverride: draft.amount, noteOverride: draft.note)
                } else if let error {
                    ContentUnavailableView("Proposta non disponibile", systemImage: "tray", description: Text(error))
                } else {
                    ProgressView("Apertura della proposta…")
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { appState.dismissQuickTransaction() }
                }
            }
        }
        .task(id: draft.id) {
            do {
                let store = try CaptureStore.container()
                self.store = store
                capture = try CaptureStore.captures(ids: [draft.id], in: store).first
                if capture == nil { error = "La proposta è già stata approvata o scartata su questo dispositivo." }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
