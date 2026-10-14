import SwiftUI

struct FormiLoadingView: View {
    enum Style {
        case regular
        case inline
    }

    let title: LocalizedStringKey
    var style: Style = .regular
    var isPlaying = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric(relativeTo: .body) private var illustrationSize = 96.0
    @State private var frameIndex = 0

    private var canAnimate: Bool {
        isPlaying && scenePhase == .active && !reduceMotion
    }

    private var displayedFrame: Int { canAnimate ? frameIndex : 0 }

    init(_ title: LocalizedStringKey = "Caricamento…", style: Style = .regular, isPlaying: Bool = true) {
        self.title = title
        self.style = style
        self.isPlaying = isPlaying
    }

    var body: some View {
        content
            .task(id: canAnimate) { await walk() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(title))
    }

    @ViewBuilder
    private var content: some View {
        if style == .inline {
            HStack(spacing: 12) {
                illustration(size: 44)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                dots
            }
        } else {
            VStack(spacing: 14) {
                illustration(size: min(illustrationSize, 128))
                dots
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func illustration(size: CGFloat) -> some View {
        Image("FormiWalkingSprite")
            .renderingMode(.original)
            .resizable()
            .frame(width: size * 4, height: size * 4)
            .offset(x: -CGFloat(displayedFrame % 4) * size,
                    y: -CGFloat(displayedFrame / 4) * size)
            .frame(width: size, height: size, alignment: .topLeading)
            .clipped()
    }

    private var dots: some View {
        HStack(spacing: 5) {
            dot(index: 0)
            dot(index: 1)
            dot(index: 2)
        }
    }

    private func dot(index: Int) -> some View {
        Circle()
            .fill(ForgiaPalette.accent)
            .frame(width: 5, height: 5)
            .opacity(canAnimate ? (displayedFrame / 6 == index ? 1 : 0.25) : 0.55)
    }

    @MainActor
    private func walk() async {
        frameIndex = 0
        guard canAnimate else { return }
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .milliseconds(80))
            } catch {
                return
            }
            frameIndex = (frameIndex + 1) % 16
        }
    }
}
