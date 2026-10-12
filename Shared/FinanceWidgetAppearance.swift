import FinanceCore
import SwiftUI
import WidgetKit

extension EnvironmentValues {
    @Entry var financeWidgetTheme: AppTheme = .formi
}

enum FinanceWidgetAppearance {
    /// The extension ships no localizations, so dates would otherwise fall back to English.
    static let locale = Locale(identifier: "it_IT")

    static var theme: AppTheme {
        FinanceWidgetAppearanceStorage.theme().flatMap(AppTheme.init(storedValue:)) ?? .formi
    }
}

/// The same language as the app's cards: a theme surface washed with the widget's own hue,
/// deeper at the heading so each widget is recognisable at a glance.
struct FinanceWidgetBackground: View {
    var tint: Color? = nil
    @Environment(\.financeWidgetTheme) private var theme
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if renderingMode == .fullColor {
            let hue = tint ?? theme.palette.accent
            ZStack {
                theme.palette.surface
                hue.opacity(colorScheme == .dark ? 0.12 : 0.08)
                LinearGradient(colors: [hue.opacity(colorScheme == .dark ? 0.24 : 0.18), hue.opacity(0)],
                               startPoint: .topLeading, endPoint: UnitPoint(x: 0.75, y: 0.85))
            }
        } else {
            Color.clear
        }
    }
}

/// Icon chip and title shared by every widget, mirroring the cards on the Today screen.
struct FinanceWidgetHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    let icon: String
    let tint: Color
    var compact = false
    @ViewBuilder var trailing: Trailing
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: compact ? 10 : 11, weight: .bold))
                .financeWidgetForeground(tint)
                .frame(width: compact ? 20 : 22, height: compact ? 20 : 22)
                .background(renderingMode == .fullColor ? tint.opacity(0.14) : Color.primary.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .widgetAccentable()
            Text(title)
                .font(.system(compact ? .caption : .subheadline, design: .rounded, weight: .semibold))
                .financeWidgetForeground(tint)
                .lineLimit(1)
            Spacer(minLength: 4)
            trailing
        }
    }
}

extension FinanceWidgetHeader where Trailing == EmptyView {
    init(title: LocalizedStringKey, icon: String, tint: Color, compact: Bool = false) {
        self.init(title: title, icon: icon, tint: tint, compact: compact) { EmptyView() }
    }
}

/// Hidden or stale data: a calm explanation instead of a bare label.
struct FinanceWidgetStateView: View {
    let hidden: Bool
    let tint: Color
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Spacer(minLength: 0)
            Image(systemName: hidden ? "eye.slash" : "arrow.clockwise")
                .font(.system(size: compact ? 18 : 20, weight: .semibold))
                .financeWidgetForeground(tint)
            Text(hidden ? "Dati nascosti" : "Da aggiornare")
                .font(.system(compact ? .subheadline : .headline, design: .rounded, weight: .semibold))
            Text(hidden
                 ? (compact ? "Attivali in Formi" : "Attiva i dati finanziari nei widget dalle impostazioni di Formi.")
                 : (compact ? "Apri Formi" : "Apri Formi per aggiornare il riepilogo."))
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(compact ? 2 : 3)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// "Aggiornato alle 13:30", or the date when the snapshot is older than today.
struct FinanceWidgetFreshness: View {
    let generatedAt: Date
    let now: Date
    var body: some View {
        Group {
            if Calendar.current.isDate(generatedAt, inSameDayAs: now) {
                Text("Aggiornato alle \(generatedAt, format: .dateTime.hour().minute())")
            } else {
                Text("Aggiornato il \(generatedAt, format: .dateTime.day().month(.abbreviated))")
            }
        }
        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
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
