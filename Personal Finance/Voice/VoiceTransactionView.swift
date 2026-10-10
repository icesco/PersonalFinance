import SwiftUI
import SwiftData
import FinanceCore

struct VoiceTransactionView: View {
    var onCompletion: () -> Void = {}
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppStateManager.self) private var appState
    @Environment(AppLock.self) private var appLock
    #if os(macOS)
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.financeTaskID) private var taskID
    #else
    @State private var sheetDetent: PresentationDetent = .height(480)
    #endif
    @Query(sort: \Conto.name) private var conti: [Conto]
    @State private var recorder = LocalVoiceRecorder()
    @State private var text = ""
    @State private var drafts: [VoiceTransactionDraft] = []
    @State private var processing = false
    @State private var requestID: UUID?
    @State private var recordingRequested = false
    @State private var prepareWhenFinished = false
    @State private var confirmed = false
    @State private var addedCount = 0
    @State private var reviewing = false
    @State private var error: String?

    #if DEBUG
    init(previewDrafts: [VoiceTransactionDraft] = [], previewText: String = "", onCompletion: @escaping () -> Void = {}) {
        self.onCompletion = onCompletion
        _drafts = State(initialValue: previewDrafts)
        _text = State(initialValue: previewText)
        _reviewing = State(initialValue: !previewDrafts.isEmpty)
    }
    #endif

    private var activeConti: [Conto] {
        conti.filter { $0.isActive == true && $0.account?.isActive == true && $0.account?.id == appState.selectedAccount?.id }
    }
    private var canSave: Bool {
        confirmed && !drafts.isEmpty && drafts.allSatisfy { reviewIssue(for: $0) == nil }
    }

    private func reviewIssue(for draft: VoiceTransactionDraft) -> String? {
        guard let amount = CaptureTextParser.decimal(draft.amount), amount > 0 else {
            return "Inserisci un importo valido."
        }
        guard draft.type != nil && draft.type != .transfer else {
            return "Scegli se è una spesa o un’entrata."
        }
        guard !draft.dateNeedsReview && draft.date.timeIntervalSince1970.isFinite else {
            return "Controlla e conferma la data."
        }
        guard let conto = activeConti.first(where: { $0.id == draft.contoID }),
              let currency = conto.account?.currency else {
            return "Scegli il conto del movimento."
        }
        guard draft.currency.isEmpty || draft.currency == currency else {
            return "La valuta deve coincidere con quella del libro (\(currency))."
        }
        guard (try? CurrencyConversion.convert(amount, rate: 1, currency: currency)) == amount else {
            return "Controlla i decimali dell’importo per la valuta del libro."
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            Group {
                if !reviewing {
                    inputSurface
                } else {
                    VoiceReviewSurface(drafts: $drafts, confirmed: $confirmed, text: text,
                        conti: activeConti, canSave: canSave, addedCount: addedCount, issue: reviewIssue,
                        onSave: { save(drafts) }, onApprove: approveOne,
                        onEditText: {
                            guard addedCount == 0 else { return }
                            reviewing = false; drafts = []; confirmed = false
                        }, onClose: close)
                }
            }
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .task(id: recordingRequested) {
                if recordingRequested {
                    await recorder.start(appendingTo: text)
                    if !recorder.isRecording { recordingRequested = false }
                }
            }
            .task(id: requestID) {
                guard let requestID else { return }
                await interpret(requestID: requestID)
            }
            .onChange(of: recorder.transcript) { _, value in text = value }
            .onChange(of: recorder.isRecording) { _, value in if !value { recordingRequested = false } }
            .onChange(of: recorder.isFinishing) { _, finishing in
                if !finishing && prepareWhenFinished {
                    prepareWhenFinished = false
                    text = recorder.transcript
                    startInterpretation()
                }
            }
            .onChange(of: drafts) { _, _ in
                confirmed = false
                if drafts.isEmpty && reviewing {
                    if addedCount > 0 { close() }
                    else { reviewing = false }
                }
                #if os(iOS)
                sheetDetent = drafts.isEmpty && !dynamicTypeSize.isAccessibilitySize ? .height(480) : .large
                #endif
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { prepareWhenFinished = false; recordingRequested = false; recorder.stop() }
            }
            .onChange(of: appLock.shouldConceal) { _, concealed in
                if concealed {
                    prepareWhenFinished = false; recordingRequested = false; recorder.stop()
                    requestID = nil; processing = false
                }
            }
            .onDisappear { prepareWhenFinished = false; recorder.stop() }
            .alert("Controlla la proposta", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 540)
        #else
        .presentationDetents([.height(480), .large], selection: $sheetDetent)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .onChange(of: dynamicTypeSize, initial: true) { _, size in
            sheetDetent = size.isAccessibilitySize || !drafts.isEmpty ? .large : .height(480)
        }
        #endif
    }

    private var inputSurface: some View {
        VoiceDictationSurface(text: $text, meter: recorder.meter,
            recording: recorder.isRecording,
            starting: recordingRequested && !recorder.isRecording,
            preparationMessage: recorder.preparationMessage,
            finishing: recorder.isFinishing, processing: processing,
            unavailableReason: activeConti.isEmpty ? "Scegli un libro con almeno un conto attivo per aggiungere movimenti." : VoiceTransactionInterpreter.unavailableReason,
            recordingError: recorder.error,
            onToggleRecording: {
                if recorder.isRecording || recordingRequested {
                    recordingRequested = false
                    if recorder.isRecording { recorder.finish() } else { recorder.stop() }
                } else { recordingRequested = true }
            },
            onPrepare: {
                if recorder.isRecording {
                    prepareWhenFinished = true
                    recordingRequested = false
                    recorder.finish()
                } else { startInterpretation() }
            }, onClose: close, onEditingChanged: { editing in
                #if os(iOS)
                sheetDetent = editing || dynamicTypeSize.isAccessibilitySize ? .large : .height(480)
                #endif
            })
    }

    private func startInterpretation() {
        processing = true
        requestID = UUID()
    }

    private func interpret(requestID id: UUID) async {
        defer { if requestID == id { processing = false } }
        do {
            let result = try await VoiceTransactionInterpreter.interpret(text, conti: activeConti, now: Date())
            try Task.checkCancellation()
            guard !result.isEmpty else { error = "Non ho riconosciuto movimenti. Specifica importo e se si tratta di una spesa o un’entrata."; return }
            drafts = result
            reviewing = true
        } catch is CancellationError {
        } catch let failure as VoiceTransactionApproval.Failure {
            if !Task.isCancelled { error = failure.localizedDescription }
        } catch {
            if !Task.isCancelled { self.error = "Non è stato possibile preparare l’elenco. Il testo è conservato: riprova o usa il modulo manuale." }
        }
    }

    private func approveOne(_ id: UUID) {
        guard let draft = drafts.first(where: { $0.id == id }), reviewIssue(for: draft) == nil else { return }
        save([draft])
    }

    private func save(_ selected: [VoiceTransactionDraft]) {
        guard !selected.isEmpty, selected.allSatisfy({ reviewIssue(for: $0) == nil }) else { return }
        do {
            try VoiceTransactionApproval.approve(selected, in: context.container)
            let ids = Set(selected.map(\.id))
            addedCount += selected.count
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
                drafts.removeAll { ids.contains($0.id) }
            }
            confirmed = false
            appState.triggerDataRefresh()
        } catch { self.error = error.localizedDescription }
    }

    private func close() {
        prepareWhenFinished = false
        recorder.stop()
        if addedCount > 0 { onCompletion() }
        #if os(macOS)
        if let taskID { dismissWindow(id: "finance-task", value: taskID) }
        else { dismiss() }
        #else
        dismiss()
        #endif
    }
}
