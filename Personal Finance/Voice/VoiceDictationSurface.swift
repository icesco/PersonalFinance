import SwiftUI
import Observation

/// Audio updates invalidate the glow rather than the transcription screen.
@MainActor @Observable final class VoiceAudioMeter {
    var level = 0.0
}

struct VoiceDictationSurface: View {
    @Binding var text: String
    let meter: VoiceAudioMeter
    var recording: Bool
    var starting: Bool
    var preparationMessage: String? = nil
    var finishing: Bool
    var processing: Bool
    var unavailableReason: String?
    var recordingError: String?
    var onToggleRecording: () -> Void
    var onPrepare: () -> Void
    var onClose: () -> Void
    var onEditingChanged: (Bool) -> Void = { _ in }
    @Namespace private var transcriptMorph
    @State private var editing = false
    @FocusState private var editorFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var busy: Bool { starting || finishing || processing }
    private var hasText: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var status: LocalizedStringKey {
        if processing { return "Preparo i movimenti" }
        if finishing { return "Un momento…" }
        if starting { return preparationMessage.map { LocalizedStringKey($0) } ?? "Avvio il microfono…" }
        if recording { return "Ti ascolto" }
        if hasText { return "Riprendi quando vuoi" }
        return "Raccontami i tuoi movimenti"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ViewThatFits(in: .vertical) {
                liveContent.frame(maxHeight: .infinity)
                ScrollView { liveContent }
                    .scrollDismissesKeyboard(.interactively)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { controls }
        .background(alignment: .bottom) {
            VoiceEdgeGlow(meter: meter, recording: recording, processing: processing || finishing,
                          enabled: unavailableReason == nil)
                .frame(height: 180)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .background(ForgiaPalette.canvas.ignoresSafeArea())
        .tint(ForgiaPalette.accent)
        .onChange(of: recording) { _, active in
            if active { editing = false; editorFocused = false; onEditingChanged(false) }
        }
    }

    private var header: some View {
        HStack {
            Label("Dettatura", systemImage: "waveform")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(ForgiaPalette.mutedText)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(ForgiaPalette.mutedText)
                    .frame(width: 52, height: 52)
                    .background(ForgiaPalette.surface, in: Circle())
                    .overlay { Circle().strokeBorder(ForgiaPalette.border) }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Chiudi dettatura")
            .accessibilityIdentifier("voice-close")
        }
        .padding(.horizontal, 20).padding(.top, 8)
    }

    private var liveContent: some View {
        VStack(spacing: 20) {
            Text(status)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .contentTransition(reduceMotion ? .identity : .opacity)
                .accessibilityAddTraits(.updatesFrequently)
            if editing {
                TextField("Parla oppure scrivi…", text: $text, axis: .vertical)
                    .font(.title3).lineLimit(3...8)
                    .focused($editorFocused)
                    .padding(16)
                    .background(ForgiaPalette.surface, in: RoundedRectangle(cornerRadius: 16))
                    .disabled(recording || busy)
                    .matchedGeometryEffect(id: "transcript", in: transcriptMorph, properties: .frame)
                    .transition(.opacity)
                    .accessibilityIdentifier("voice-text")
            } else if hasText {
                Text(text)
                    .font(.title3)
                    .multilineTextAlignment(.center).lineSpacing(4).lineLimit(4)
                    .textSelection(.enabled)
                    .matchedGeometryEffect(id: "transcript", in: transcriptMorph, properties: .frame)
                    .transition(.opacity)
                    .accessibilityIdentifier("voice-transcript")
            } else {
                Text("“Ho speso 3 euro al bar\ne 5 euro al supermercato.”")
                    .font(.body).foregroundStyle(ForgiaPalette.mutedText)
                    .multilineTextAlignment(.center).lineSpacing(4)
            }
            if hasText && !editing {
                VoiceLiveCards(text: text)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
            }
            if let message = unavailableReason ?? recordingError {
                Label(message, systemImage: "info.circle")
                    .font(.footnote).foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            if text.count > 4_000 {
                Text("Usa un testo più breve, fino a 4.000 caratteri.")
                    .font(.footnote).foregroundStyle(ForgiaPalette.deficit)
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: recording)
        .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: busy)
        .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: editing)
        .padding(.horizontal, 28).padding(.vertical, 16)
        .frame(maxWidth: 620)
        .frame(maxWidth: .infinity)
    }

    private var primaryTitle: LocalizedStringKey {
        if processing { return "Preparo l’elenco…" }
        if finishing { return "Metto in pausa…" }
        if starting { return "Avvio il microfono…" }
        if recording { return "Pausa" }
        return hasText ? "Rivedi movimenti" : "Inizia a dettare"
    }

    private var primarySymbol: String {
        recording ? "pause.fill" : (hasText ? "arrow.right" : "mic.fill")
    }

    private var canPrepare: Bool {
        hasText && !busy && unavailableReason == nil && text.count <= 4_000
    }

    private var controls: some View {
        VStack(spacing: 12) {
            VoicePrimaryControlLayout(compact: recording ? 1 : 0) {
                Button {
                    if recording || !hasText { onToggleRecording() }
                    else { onPrepare() }
                } label: {
                    HStack(spacing: 10) {
                        if busy { ProgressView().tint(ForgiaPalette.onAccent) }
                        else {
                            Image(systemName: primarySymbol)
                                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                        }
                        Text(primaryTitle)
                            .contentTransition(reduceMotion ? .identity : .interpolate)
                    }
                    .font(.body.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .frame(maxWidth: .infinity).frame(minHeight: 56)
                }
                .buttonStyle(VoicePrimaryButtonStyle(cornerRadius: recording ? 28 : 18))
                .disabled(busy || unavailableReason != nil || (!recording && hasText && !canPrepare))
                .accessibilityLabel(recording ? "Metti in pausa la dettatura" : primaryTitle)
                .accessibilityIdentifier(recording || !hasText ? "voice-record" : "voice-interpret")
            }

            if recording {
                Button(action: onPrepare) {
                    Label("Rivedi movimenti", systemImage: "arrow.right")
                        .font(.body.weight(.medium))
                        .padding(.horizontal, 16).frame(minHeight: 50)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(ForgiaPalette.mutedText)
                .disabled(!canPrepare)
                .accessibilityIdentifier("voice-interpret")
                .transition(.opacity)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        editButton
                        if hasText { resumeButton }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    VStack(spacing: 10) {
                        editButton
                        if hasText { resumeButton }
                    }
                }
                .buttonStyle(VoiceSecondaryButtonStyle())
                .transition(.opacity)
            }

            Label("Solo sul tuo dispositivo", systemImage: "lock")
                .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: recording)
        .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: editing)
        .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 16)
        .frame(maxWidth: 620)
        .frame(maxWidth: .infinity)
    }

    private var editButton: some View {
        Button {
            editing.toggle()
            onEditingChanged(editing)
            editorFocused = editing
        } label: {
            Label(editing ? "Chiudi tastiera" : "Modifica testo",
                  systemImage: editing ? "keyboard.chevron.compact.down" : "keyboard")
                .contentTransition(reduceMotion ? .identity : .opacity)
        }
        .disabled(busy)
        .accessibilityIdentifier("voice-edit")
    }

    private var resumeButton: some View {
        Button(action: onToggleRecording) { Label("Riprendi", systemImage: "mic.fill") }
            .disabled(busy || unavailableReason != nil)
            .accessibilityIdentifier("voice-record")
    }

}

/// Interpolates finite widths so the pause capsule can expand into the review button.
private struct VoicePrimaryControlLayout: Layout {
    var compact: Double
    var animatableData: Double {
        get { compact }
        set { compact = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let fullWidth = proposal.width ?? 572
        let width = fullWidth + (min(fullWidth, 196) - fullWidth) * compact
        let size = subviews[0].sizeThatFits(ProposedViewSize(width: width, height: nil))
        return CGSize(width: fullWidth, height: size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = bounds.width + (min(bounds.width, 196) - bounds.width) * compact
        subviews[0].place(at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center,
                          proposal: ProposedViewSize(width: width, height: bounds.height))
    }
}

struct VoicePrimaryButtonStyle: ButtonStyle {
    let cornerRadius: CGFloat
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(ForgiaPalette.onAccent)
            .background(ForgiaPalette.accent, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .opacity(enabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct VoiceSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(ForgiaPalette.accent)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .frame(maxWidth: .infinity).frame(minHeight: 50)
            .background(ForgiaPalette.surface, in: Capsule())
            .overlay { Capsule().strokeBorder(ForgiaPalette.border) }
            .contentShape(Capsule())
            .opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct VoiceLiveCards: View {
    let text: String
    @State private var cards: [Card] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .subheadline) private var stripHeight = 64.0

    private struct Card: Identifiable {
        let id: UUID
        let token: VoiceLiveToken
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !cards.isEmpty {
                Text("Anteprima provvisoria")
                    .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                ViewThatFits(in: .horizontal) {
                    cardRow.fixedSize(horizontal: true, vertical: false)
                    ScrollView(.horizontal) {
                        cardRow.padding(.vertical, 2)
                    }
                    .scrollIndicators(.hidden)
                    .frame(height: stripHeight)
                }
            }
        }
        .onChange(of: text, initial: true) { _, transcript in
            let tokens = VoiceLivePreview.tokens(in: transcript)
            let updated = tokens.map { token in
                Card(id: cards.first { $0.token.sourceOffset == token.sourceOffset }?.id ?? UUID(), token: token)
            }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { cards = updated }
        }
        .accessibilityIdentifier("voice-live-preview")
    }

    private var cardRow: some View {
        HStack(spacing: 10) {
            ForEach(cards) { card in
                VoiceLiveCard(token: card.token).transition(.opacity)
            }
        }
    }
}

private struct VoiceLiveCard: View {
    let token: VoiceLiveToken
    @ScaledMetric(relativeTo: .subheadline) private var contentWidth = 120.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var symbol: String {
        switch token.direction {
        case .expense: "arrow.up.right"
        case .income: "arrow.down.left"
        case nil: "waveform"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(token.direction == .expense ? ForgiaPalette.spending : ForgiaPalette.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(token.amount, format: .currency(code: token.currency))
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .contentTransition(reduceMotion ? .identity : .numericText())
                if !token.title.isEmpty {
                    Text(verbatim: token.title)
                        .contentTransition(reduceMotion ? .identity : .opacity)
                        .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                        .lineLimit(1)
                } else {
                    Text("In ascolto…")
                        .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                }
            }
        }
        .frame(width: contentWidth, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(ForgiaPalette.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(ForgiaPalette.accent.opacity(0.18)) }
        .accessibilityElement(children: .combine)
    }
}

private struct VoiceEdgeGlow: View {
    let meter: VoiceAudioMeter
    let recording: Bool
    let processing: Bool
    let enabled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let active = enabled && (recording || processing)
        let level = !enabled ? 0 : (reduceMotion ? (active ? 0.35 : 0.04) :
            (recording ? min(max(meter.level, 0), 1) : (processing ? 0.4 : 0.04)))
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || !active)) { timeline in
            VoiceGlowField(level: level,
                           phase: reduceMotion || !active ? 0 : timeline.date.timeIntervalSinceReferenceDate,
                           processing: processing, dark: scheme == .dark,
                           accent: ForgiaPalette.accent, warm: ForgiaPalette.spending)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: level)
        }
    }
}

private struct VoiceGlowField: View, Animatable {
    var level: Double
    let phase: Double
    let processing: Bool
    let dark: Bool
    let accent: Color
    let warm: Color
    var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let energy = min(max(level, 0), 1)
            let travel = processing ? sin(phase * 0.9) * 0.15 : sin(phase * 0.7) * 0.035
            let height = size.height * (dark ? 0.12 + energy * 0.85 : 0.35 + energy * 1.02)
            let opacity = dark ? 0.68 * (0.2 + energy * 0.8) : 0.88 * (0.36 + energy * 0.64)
            glow(context: context, size: size, x: 0.40 + travel, width: 0.55,
                 height: height, color: accent, opacity: opacity)
            glow(context: context, size: size, x: 0.67 - travel * 0.6, width: 0.40,
                 height: height * (dark ? 0.7 : 0.85), color: warm, opacity: opacity * (dark ? 0.6 : 0.9))
            glow(context: context, size: size, x: 0.5 + travel * 0.3, width: 0.3,
                 height: height * (dark ? 0.24 : 0.38), color: accent, opacity: opacity * (dark ? 0.7 : 0.95))
        }
        .saturation(dark ? 1 : 1.6)
        .brightness(dark ? 0 : 0.04)
    }

    private func glow(context: GraphicsContext, size: CGSize, x: Double, width: Double,
                      height: Double, color: Color, opacity: Double) {
        var layer = context
        layer.translateBy(x: size.width * x, y: size.height + 3)
        layer.scaleBy(x: size.width * width, y: max(height, 1))
        layer.fill(Path(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2)),
                   with: .radialGradient(Gradient(stops: [
                    .init(color: color.opacity(opacity), location: 0),
                    .init(color: color.opacity(opacity * 0.6), location: 0.3),
                    .init(color: color.opacity(opacity * 0.18), location: 0.65),
                    .init(color: .clear, location: 1)
                   ]), center: .zero, startRadius: 0, endRadius: 1))
    }
}

#Preview("In ascolto") {
    VoiceDictationSurface(text: .constant("Ho speso 3 euro al bar e 5 euro al supermercato."),
        meter: VoiceAudioMeter(), recording: true, starting: false, finishing: false, processing: false,
        onToggleRecording: {}, onPrepare: {}, onClose: {})
        .preferredColorScheme(.dark)
}
