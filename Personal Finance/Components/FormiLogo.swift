import SwiftUI

/// The Formi badge: the ant carrying a seed on the app's green ground.
/// It is the same artwork as the app icon, so every screen shows one brand mark.
struct FormiLogo: View {
    var size: CGFloat = 42

    var body: some View {
        Image("FormiLogo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.227, style: .continuous))
            .accessibilityLabel("Formi")
    }
}

#Preview {
    HStack(spacing: 16) {
        FormiLogo(size: 28)
        FormiLogo()
        FormiLogo(size: 96)
    }
    .padding()
}
