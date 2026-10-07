import SwiftUI

struct CalendarNavigationHeader: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    let palette: CalendarPalette
    let typography: CalendarTypography
    let previous: () -> Void
    let next: () -> Void

    var body: some View {
        HStack {
            navButton("chevron.left", action: previous)
            Spacer()
            Text(title)
                .font(typography.monthTitle)
                .foregroundStyle(palette.foreground)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: title)
            Spacer()
            navButton("chevron.right", action: next)
        }
        .padding(.horizontal, CalendarSpacing.large)
        .padding(.vertical, CalendarSpacing.medium)
    }

    private func navButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(palette.accent)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol == "chevron.left" ? "Mese precedente" : "Mese successivo")
    }
}
