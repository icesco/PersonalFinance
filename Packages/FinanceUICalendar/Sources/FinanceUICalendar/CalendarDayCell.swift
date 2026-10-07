import SwiftUI

struct CalendarDayCell: View {
    let date: Date
    var calendar: Calendar = .current
    let isSelected: Bool
    let isToday: Bool
    let isInCurrentMonth: Bool
    let palette: CalendarPalette
    let typography: CalendarTypography
    /// Colori (unici, nell'ordine di comparsa) dei task del giorno, max 3 pallini.
    let taskColors: [Color]
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 3) {
                Text("\(calendar.component(.day, from: date))")
                    .font(isToday || isSelected ? typography.dayNumberEmphasized : typography.dayNumber)
                    .foregroundStyle(textColor)
                    .monospacedDigit()

                HStack(spacing: 3) {
                    ForEach(Array(taskColors.prefix(3).enumerated()), id: \.offset) { _, c in
                        Circle()
                            .fill(isToday ? .white : c)
                            .frame(width: 5, height: 5)
                    }
                }
                .frame(height: 5)
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(selectionBackground)
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(!isInCurrentMonth)
        .accessibilityLabel(Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(calendar.locale ?? .current))))
        .accessibilityValue(isSelected ? "Giorno selezionato" : taskColors.isEmpty ? "Nessun movimento" : "Movimenti presenti")
        .accessibilityIdentifier("finance-calendar-day-\(calendar.component(.day, from: date))")
    }

    @ViewBuilder
    private var selectionBackground: some View {
        if isToday {
            RoundedRectangle(cornerRadius: 10)
                .fill(palette.accent)
                .padding(.horizontal, 4)
        } else if isSelected {
            RoundedRectangle(cornerRadius: 10)
                .stroke(palette.accent, lineWidth: 1.5)
                .padding(.horizontal, 4)
        }
    }

    private var textColor: Color {
        if !isInCurrentMonth { return palette.foregroundSecondary.opacity(0.4) }
        if isToday { return .white }
        return palette.foreground
    }
}
