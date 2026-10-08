import FinanceCore
import SwiftUI
import WidgetKit

extension EnvironmentValues {
    @Entry var financeWidgetTheme: AppTheme = .formi
}

enum FinanceWidgetAppearance {
    static var theme: AppTheme {
        FinanceWidgetAppearanceStorage.theme().flatMap(AppTheme.init(storedValue:)) ?? .formi
    }
}

/// Quiet depth using the same canvas and accent surface as the selected app theme.
struct FinanceWidgetBackground: View {
    @Environment(\.financeWidgetTheme) private var theme
    @Environment(\.widgetRenderingMode) private var renderingMode
    var body: some View {
        if renderingMode == .fullColor {
        LinearGradient(stops: [.init(color: theme.palette.canvas, location: 0),
                               .init(color: theme.palette.canvas, location: 0.5),
                               .init(color: theme.palette.accentSurface, location: 1)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
        } else {
            Color.clear
        }
    }
}

/// Opaque semantic foregrounds keep glyphs readable when the system replaces their colours.
private struct FinanceWidgetForeground: ViewModifier {
    let color: Color
    @Environment(\.widgetRenderingMode) private var renderingMode
    func body(content: Content) -> some View {
        content.foregroundStyle(renderingMode == .fullColor ? color : .primary)
    }
}

extension View {
    func financeWidgetForeground(_ color: Color) -> some View {
        modifier(FinanceWidgetForeground(color: color))
    }
}
