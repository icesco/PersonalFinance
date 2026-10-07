import SwiftUI

/// Griglia mensile con header di navigazione, swipe tra mesi, celle giorno
/// con pallini colorati per categoria di task.
///
/// Il package non conosce il modello dati dell'app: il client passa una
/// closure `tasksForDate` che restituisce i `CalendarTask` di quel giorno.
public struct MonthlyCalendarView: View {
    @Binding private var selectedDate: Date
    @Binding private var currentMonth: Date
    private let palette: CalendarPalette
    private let typography: CalendarTypography
    private let tasksForDate: (Date) -> [CalendarTask]
    private let calendar: Calendar

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var navigationDirection: CalendarNavigationDirection = .forward
    @State private var dragOffset: CGFloat = 0

    public init(
        selectedDate: Binding<Date>,
        currentMonth: Binding<Date>,
        palette: CalendarPalette,
        typography: CalendarTypography = .system,
        calendar: Calendar = .current,
        tasksForDate: @escaping (Date) -> [CalendarTask]
    ) {
        self._selectedDate = selectedDate
        self._currentMonth = currentMonth
        self.palette = palette
        self.typography = typography
        self.calendar = calendar
        self.tasksForDate = tasksForDate
    }

    public var body: some View {
        let days = generateMonthDays()
        // Precomputo i pallini per ogni cella: evita 42 chiamate a `tasksForDate`
        // + 42 passate di de-dupe colori dentro il ForEach.
        let colorsByDay = Dictionary(uniqueKeysWithValues: days.map { ($0, uniqueColors(tasksForDate($0))) })

        VStack(spacing: CalendarSpacing.small) {
            CalendarNavigationHeader(
                title: monthTitle,
                palette: palette,
                typography: typography,
                previous: previousMonth,
                next: nextMonth
            )

            weekdayHeader

            monthGrid(days: days, colorsByDay: colorsByDay)
                .id(monthKey)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: navigationDirection == .forward ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: navigationDirection == .forward ? .leading : .trailing).combined(with: .opacity)
                    )
                )
                .offset(x: reduceMotion ? 0 : calendarRubberBandOffset(dragOffset))
                .gesture(swipeGesture)
        }
    }

    private var weekdayHeader: some View {
        HStack {
            ForEach(Array(orderedWeekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(typography.weekdaySymbol)
                    .foregroundStyle(palette.foregroundSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, CalendarSpacing.medium)
    }

    private func monthGrid(days: [Date], colorsByDay: [Date: [Color]]) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7),
            spacing: 2
        ) {
            ForEach(days, id: \.self) { date in
                cell(for: date, colors: colorsByDay[date] ?? [])
            }
        }
        .padding(.horizontal, CalendarSpacing.small)
    }

    private func cell(for date: Date, colors: [Color]) -> some View {
        let isInMonth = calendar.isDate(date, equalTo: currentMonth, toGranularity: .month)
        return CalendarDayCell(
            date: date,
            calendar: calendar,
            isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
            isToday: calendar.isDateInToday(date),
            isInCurrentMonth: isInMonth,
            palette: palette,
            typography: typography,
            taskColors: colors,
            onTap: {
                guard isInMonth else { return }
                selectedDate = calendar.startOfDay(for: date)
            }
        )
    }

    private func uniqueColors(_ tasks: [CalendarTask]) -> [Color] {
        var seen = Set<String>()
        var result: [Color] = []
        for t in tasks where seen.insert(t.categoryID).inserted {
            result.append(t.categoryColor)
        }
        return result
    }

    private func generateMonthDays() -> [Date] {
        monthGridDates(containing: currentMonth, calendar: calendar)
    }

    private var orderedWeekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let firstIndex = calendar.firstWeekday - 1
        return (0..<7).map { symbols[(firstIndex + $0) % 7] }
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .current
        formatter.setLocalizedDateFormatFromTemplate("MMMMyyyy")
        return formatter.string(from: currentMonth).capitalized
    }

    private var monthKey: Date {
        calendar.dateInterval(of: .month, for: currentMonth)?.start ?? currentMonth
    }

    private func previousMonth() {
        navigationDirection = .backward
        withAnimation(reduceMotion ? nil : .calendarEase) {
            currentMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
        }
    }

    private func nextMonth() {
        navigationDirection = .forward
        withAnimation(reduceMotion ? nil : .calendarEase) {
            currentMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) ?? currentMonth
        }
    }

    private var swipeGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if abs(value.translation.width) > abs(value.translation.height) {
                    dragOffset = value.translation.width
                }
            }
            .onEnded { value in
                let threshold: CGFloat = 60
                if abs(value.translation.width) > abs(value.translation.height) {
                    if value.translation.width > threshold {
                        previousMonth()
                    } else if value.translation.width < -threshold {
                        nextMonth()
                    }
                }
                withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)) {
                    dragOffset = 0
                }
            }
    }
}
