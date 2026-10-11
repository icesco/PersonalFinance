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
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Impostazioni")
            .accessibilityIdentifier("navigation-settings")
        }
        #endif
    }
}
