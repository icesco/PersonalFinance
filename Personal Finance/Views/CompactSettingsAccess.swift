import SwiftUI

struct CompactSettingsButton: View {
    @Environment(AppStateManager.self) private var appState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        #if os(iOS)
        if horizontalSizeClass == .compact {
            Button {
                appState.selectTab(.settings)
            } label: {
                Image(systemName: "gearshape")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .frame(width: 44, height: 44)
            .accessibilityLabel("Impostazioni")
            .accessibilityIdentifier("navigation-settings")
        }
        #endif
    }
}
