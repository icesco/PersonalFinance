import SwiftUI

extension View {
    /// On Mac an empty list uses the available pane, with compact, clickable actions.
    func financeEmptyOverlay<Empty: View>(isPresented: Bool, @ViewBuilder content: () -> Empty) -> some View {
        #if os(macOS)
        self
            .accessibilityHidden(isPresented)
            .overlay {
                if isPresented {
                    content()
                        .frame(maxWidth: 480)
                        .padding(24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(ForgiaPalette.canvas)
                }
            }
        #else
        self
        #endif
    }
}
