import SwiftUI

enum FormiEmptyArtwork: String {
    case peeking = "FormiEmptyPeeking"
    case carrying = "FormiEmptyCarrying"
    case origami = "FormiEmptyOrigami"
    case portrait = "FormiEmptyPortrait"
}

struct FormiEmptyIllustration: View {
    let artwork: FormiEmptyArtwork
    @ScaledMetric(relativeTo: .title2) private var size = 156.0

    var body: some View {
        Image(artwork.rawValue)
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: min(size, 180), height: min(size, 180))
            .accessibilityHidden(true)
    }
}

struct FormiEmptyStateLabel: View {
    let title: LocalizedStringKey
    let artwork: FormiEmptyArtwork

    var body: some View {
        VStack(spacing: 16) {
            FormiEmptyIllustration(artwork: artwork)
            Text(title)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
        }
    }
}
