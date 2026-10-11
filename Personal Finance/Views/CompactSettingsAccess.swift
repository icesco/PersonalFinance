import SwiftUI

extension View {
    func compactSettingsAccess(isActive: Bool = true) -> some View {
        modifier(CompactSettingsAccess(isActive: isActive))
    }
}

private struct CompactSettingsAccess: ViewModifier {
    @Environment(AppStateManager.self) private var appState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let isActive: Bool

    @ViewBuilder func body(content: Content) -> some View {
        #if os(iOS)
        if isActive && horizontalSizeClass == .compact {
            content
                .toolbar(.visible, for: .navigationBar)
                .toolbarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            appState.selectTab(.settings)
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel("Impostazioni")
                        .accessibilityIdentifier("navigation-settings")
                    }
                }
        } else {
            content
        }
        #else
        content
        #endif
    }
}
