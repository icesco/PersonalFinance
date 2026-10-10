import SwiftUI

struct VoiceTransactionEntryButton: View {
    let onComplete: () -> Void
    var onOpen: () -> Void = {}
    @State private var showingVoice = false
    @State private var savedMovements = false

    var body: some View {
        Button {
            onOpen()
            savedMovements = false
            showingVoice = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "mic.fill")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .background(ForgiaPalette.accent.opacity(0.1), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text("Aggiungi con la voce").font(.body.weight(.semibold))
                    Text("Detta uno o più movimenti e poi controllali.")
                        .font(.subheadline).foregroundStyle(ForgiaPalette.mutedText)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(ForgiaPalette.accent)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ForgiaPalette.surface, in: RoundedRectangle(cornerRadius: 22))
            .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(ForgiaPalette.border) }
            .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("transaction-voice-entry")
        #if os(macOS)
        .financePresentation(isPresented: $showingVoice, title: "Aggiungi con la voce", width: 600, height: 720) {
            VoiceTransactionView(onCompletion: { savedMovements = true })
        }
        .onChange(of: showingVoice) { _, showing in
            if !showing && savedMovements { onComplete() }
        }
        #else
        .sheet(isPresented: $showingVoice, onDismiss: {
            if savedMovements { onComplete() }
        }) {
            VoiceTransactionView(onCompletion: { savedMovements = true })
        }
        #endif
    }
}
