//
//  CryptoDashboardView.swift
//  Personal Finance
//
//  Crypto-style dashboard with dark gradient, hero balance, and custom bottom sheet
//

import SwiftUI
import SwiftData
import Charts
import FinanceCore

// MARK: - Custom Bottom Sheet

struct DraggableBottomSheet<Content: View>: View {
    @Binding var selectedDetent: SheetDetent
    @Binding var currentSheetHeight: CGFloat  // Exposed for real-time updates
    let detents: [SheetDetent]
    let content: Content
    var onDismiss: (() -> Void)?

    @State private var dragOffset: CGFloat = 0
    @GestureState private var isDragging = false

    init(
        selectedDetent: Binding<SheetDetent>,
        currentSheetHeight: Binding<CGFloat>,
        detents: [SheetDetent],
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self._selectedDetent = selectedDetent
        self._currentSheetHeight = currentSheetHeight
        self.detents = detents.sorted { $0.height(in: 0) < $1.height(in: 0) }
        self.onDismiss = onDismiss
        self.content = content()
    }

    var body: some View {
        GeometryReader { geometry in
            let safeAreaBottom = geometry.safeAreaInsets.bottom
            let maxHeight = geometry.size.height + safeAreaBottom
            let baseHeight = selectedDetent.height(in: maxHeight)
            let effectiveHeight = baseHeight + dragOffset
            let offsetY = maxHeight - baseHeight - dragOffset

            // Calculate progress (0 = compact, 1 = full screen)
            let minHeight = detents.first?.height(in: maxHeight) ?? 280
            let maxDetentHeight = maxHeight
            let progress = max(0, min(1, (effectiveHeight - minHeight) / (maxDetentHeight - minHeight)))

            // Tab bar height (approximate: 49pt bar + safe area indicator)
            let tabBarHeight: CGFloat = 49 + safeAreaBottom

            // Dynamic values based on progress
            let backgroundOpacity = 0.7 + (0.3 * progress)      // 0.7 → 1.0
            let cornerRadius = 24 - (16 * progress)              // 24 → 8
            let bottomCornerRadius = 16 * (1 - progress)         // 16 → 0 (rounded when compact, square when expanded)
            let horizontalPadding = 12 - (12 * progress)         // 12 → 0
            let sheetBottomPadding = tabBarHeight * (1 - progress) - safeAreaBottom  // Sits above tab bar when compact, extends to bottom when expanded

            VStack(spacing: 0) {
                // Header with drag handle and dismiss button
                ZStack {
                    // Drag handle (centered)
                    Capsule()
                        .fill(Color.white.opacity(0.4))
                        .frame(width: 36, height: 5)

                    // Dismiss button (right aligned)
                    if let onDismiss = onDismiss {
                        HStack {
                            Spacer()
                            Button {
                                onDismiss()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.6))
                                    .frame(width: 28, height: 28)
                                    .background(Color.white.opacity(0.1))
                                    .clipShape(Circle())
                            }
                            .padding(.trailing, 12)
                        }
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 8)

                // Content
                content

                // Extra space for safe area when fully expanded
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(
                UnevenRoundedRectangle(topLeadingRadius: cornerRadius, bottomLeadingRadius: bottomCornerRadius, bottomTrailingRadius: bottomCornerRadius, topTrailingRadius: cornerRadius)
                    .fill(Color(hex: "#1C1C1E").opacity(backgroundOpacity))
            )
            .padding(.horizontal, horizontalPadding)
            .padding(.bottom, sheetBottomPadding) // Dynamic: sits above tab bar when compact
            .offset(y: max(offsetY, 0))
            .gesture(
                DragGesture()
                    .updating($isDragging) { _, state, _ in
                        state = true
                    }
                    .onChanged { value in
                        // Negative translation = drag up = expand (positive offset)
                        dragOffset = -value.translation.height
                        // Update the exposed height in real-time
                        currentSheetHeight = effectiveHeight
                    }
                    .onEnded { value in
                        // Calculate projected height based on drag direction
                        let projectedHeight = baseHeight - value.translation.height - value.predictedEndTranslation.height * 0.3
                        let targetDetent = closestDetent(to: projectedHeight, in: maxHeight)
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            selectedDetent = targetDetent
                            dragOffset = 0
                            currentSheetHeight = targetDetent.height(in: maxHeight)
                        }
                    }
            )
            .animation(isDragging ? nil : .spring(response: 0.35, dampingFraction: 0.8), value: selectedDetent)
            .onAppear {
                // Initialize the current height
                currentSheetHeight = baseHeight
            }
            .onChange(of: selectedDetent) { _, newDetent in
                currentSheetHeight = newDetent.height(in: maxHeight)
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private func closestDetent(to height: CGFloat, in maxHeight: CGFloat) -> SheetDetent {
        detents.min(by: { abs($0.height(in: maxHeight) - height) < abs($1.height(in: maxHeight) - height) }) ?? selectedDetent
    }
}

enum SheetDetent: Equatable, Hashable {
    case height(CGFloat)
    case fraction(CGFloat)

    func height(in containerHeight: CGFloat) -> CGFloat {
        switch self {
        case .height(let h): return h
        case .fraction(let f): return containerHeight * f
        }
    }
}

// MARK: - Chart Period

enum ChartPeriod: String, CaseIterable, Identifiable {
    case oneMonth = "1M"
    case threeMonths = "3M"
    case sixMonths = "6M"
    case oneYear = "1A"
    case all = "Tutto"

    var id: String { rawValue }

    var monthsCount: Int? {
        switch self {
        case .oneMonth: return 1
        case .threeMonths: return 3
        case .sixMonths: return 6
        case .oneYear: return 12
        case .all: return nil // All available data
        }
    }

    /// Whether X-axis should show weeks instead of months
    var useWeeklyAxis: Bool {
        self == .oneMonth
    }

    /// Calendar component for X-axis stride
    var axisStrideComponent: Calendar.Component {
        useWeeklyAxis ? .weekOfMonth : .month
    }

    /// Number of units between X-axis labels
    var axisStrideCount: Int {
        switch self {
        case .oneMonth: return 1  // Every week
        case .threeMonths: return 1
        case .sixMonths: return 1
        case .oneYear: return 2
        case .all: return 3
        }
    }

    var displayName: String {
        switch self {
        case .oneMonth: return "1 Mese"
        case .threeMonths: return "3 Mesi"
        case .sixMonths: return "6 Mesi"
        case .oneYear: return "1 Anno"
        case .all: return "Tutto"
        }
    }
}

// MARK: - Multi-Account Balance History

struct AccountBalanceDataPoint: Identifiable {
    let id = UUID()
    let accountId: UUID
    let accountName: String
    let date: Date
    let balance: Decimal
    let color: Color
}

struct CryptoDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStateManager.self) private var appState

    @Query private var allAccounts: [Account]

    // Sheet detent tracking
    @State private var selectedDetent: SheetDetent = .height(280)
    @State private var currentSheetHeight: CGFloat = 280  // Real-time height during drag
    @State private var isSheetDismissed: Bool = false  // When true, sheet is hidden and FAB is shown

    // Chart period
    @State private var selectedPeriod: ChartPeriod = .sixMonths
    @State private var selectedMonth: Date = Date() // For 1M period - which specific month

    // Chart Y-axis visibility (toggle on tap)
    @State private var showYAxis: Bool = false

    // Fetched data
    @State private var monthlyIncome: Decimal = 0
    @State private var monthlyExpenses: Decimal = 0
    @State private var previousMonthBalance: Decimal = 0
    @State private var balanceHistory: [BalanceDataPoint] = []
    @State private var multiAccountHistory: [AccountBalanceDataPoint] = []
    @State private var multiContoHistory: [AccountBalanceDataPoint] = []  // Reuse same struct for conti
    @State private var contiChanges: [UUID: Decimal] = [:]
    @State private var recentTransactions: [FinanceTransaction] = []
    @State private var hasTransactionsInPeriod: Bool = true

    private var theme: AppTheme { appState.themeManager.currentTheme }

    // Custom detents
    private let sheetDetents: [SheetDetent] = [
        .height(280),      // Compatto
        .fraction(0.5),    // Medio
        .fraction(0.85),   // Espanso
        .fraction(1.0)     // Tutto schermo
    ]

    // Layout proportions (as fractions of screen height)
    private struct LayoutProportions {
        static let balanceHero: CGFloat = 0.09      // ~9% for balance display
        static let quickActions: CGFloat = 0.11     // ~11% for action buttons
        static let topPadding: CGFloat = 0.01       // ~1% top padding + nav bar
        static let chartMinimum: CGFloat = 0.10     // Minimum 10% for chart
    }

    // Chart height adapts based on available space above the sheet (real-time during drag)
    private func chartHeight(for screenHeight: CGFloat, safeAreaTop: CGFloat) -> CGFloat {
        // Use currentSheetHeight for real-time updates during drag
        let sheetHeight = currentSheetHeight

        // Total available height (screen minus safe areas are already excluded by GeometryReader)
        // We need to account for: nav bar (~44pt) + VStack paddings + spacing
        let navBarAndPadding: CGFloat = 50  // nav bar + top padding
        let vstackSpacing: CGFloat = 24     // 2 x 12pt spacing between sections

        // Fixed content heights (more accurate pixel-based values for iPhone)
        let balanceHeroHeight: CGFloat = 80   // Balance text + change indicator
        let quickActionsHeight: CGFloat = 90  // Button circles + labels

        let fixedContentHeight = navBarAndPadding + balanceHeroHeight + quickActionsHeight + vstackSpacing

        // Available space for the chart - fill completely to sheet
        let availableSpace = screenHeight - sheetHeight - fixedContentHeight

        // Minimum height
        let minimumHeight: CGFloat = 80

        // Use all available space, but never less than minimum
        return max(minimumHeight, availableSpace)
    }

    // Active accounts (deduplicated by ID)
    private var activeAccounts: [Account] {
        var seen = Set<UUID>()
        return allAccounts.filter { $0.isActive == true }.filter { account in
            guard !seen.contains(account.id) else { return false }
            seen.insert(account.id)
            return true
        }
    }

    // Determine which accounts to show
    private var displayedAccounts: [Account] {
        if appState.showAllAccounts {
            return activeAccounts
        } else if let account = appState.selectedAccount {
            return [account]
        }
        return []
    }

    // All conti from displayed accounts (filtered by selection)
    private var allDisplayedConti: [Conto] {
        // If a specific conto is selected, return only that
        if !appState.showAllConti, let selectedConto = appState.selectedConto {
            return [selectedConto]
        }

        // Otherwise return all conti from displayed accounts (deduplicated)
        var seen = Set<UUID>()
        return displayedAccounts.flatMap { $0.activeConti }.filter { conto in
            guard !seen.contains(conto.id) else { return false }
            seen.insert(conto.id)
            return true
        }
    }

    // Total balance across displayed accounts
    private var totalBalance: Decimal {
        displayedAccounts.reduce(Decimal(0)) { $0 + $1.totalBalance }
    }

    private var absoluteChange: Decimal {
        totalBalance - previousMonthBalance
    }

    private var percentageChange: Double {
        guard previousMonthBalance != 0 else { return 0 }
        let change = (absoluteChange / previousMonthBalance) * 100
        return NSDecimalNumber(decimal: change).doubleValue
    }

    private var isPositiveChange: Bool { absoluteChange >= 0 }

    // Display name for libro/account switcher
    private var displayName: String {
        if appState.showAllAccounts {
            return "Tutti i Libri"
        }
        if let libro = appState.selectedAccount {
            if appState.showAllConti {
                return libro.name ?? "Libro"
            } else if let conto = appState.selectedConto {
                return conto.name ?? "Account"
            }
        }
        return "Libro"
    }

    // Predefined colors for multi-account chart
    private let accountColors: [Color] = [
        .blue, .green, .orange, .purple, .pink, .cyan, .yellow, .red, .mint, .indigo
    ]

    private func colorForAccount(at index: Int) -> Color {
        accountColors[index % accountColors.count]
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                // Use the same reference frame as the sheet (includes bottom safe area)
                let totalHeight = geometry.size.height + geometry.safeAreaInsets.bottom
                // When sheet is dismissed, use compact height (280) for chart calculation
                let effectiveSheetHeight = isSheetDismissed ? 280 : currentSheetHeight
                let sheetTop = totalHeight - effectiveSheetHeight  // Y position where sheet starts

                // Fixed content: top padding + balance hero + spacing + quick actions + spacing
                let fixedContentTop: CGFloat = 4 + 80 + 12 + 90 + 12  // = 198pt

                // Chart should fill from fixed content to sheet top (with small 8pt margin)
                let dynamicChartHeight = max(80, sheetTop - fixedContentTop - 8)

                ZStack {
                    // Gradient Background
                    gradientBackground

                    // Main content (behind sheet) - aligned to top
                    VStack(spacing: 12) {
                        // Balance Hero
                        balanceHeroSection

                        // Quick Actions
                        quickActionsSection

                        // Balance Chart - fills remaining space to sheet
                        balanceChartSection(height: dynamicChartHeight)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                    // Custom bottom sheet (doesn't cover tab bar)
                    if !isSheetDismissed {
                        DraggableBottomSheet(
                            selectedDetent: $selectedDetent,
                            currentSheetHeight: $currentSheetHeight,
                            detents: sheetDetents,
                            onDismiss: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    isSheetDismissed = true
                                }
                            }
                        ) {
                            sheetContent
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    // FAB to restore sheet when dismissed
                    if isSheetDismissed {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Button {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        selectedDetent = .height(280)
                                        isSheetDismissed = false
                                    }
                                } label: {
                                    Image(systemName: "list.bullet.rectangle")
                                        .font(.system(size: 22, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .frame(width: 56, height: 56)
                                        .background(theme.color)
                                        .clipShape(Circle())
                                        .shadow(color: theme.color.opacity(0.4), radius: 8, x: 0, y: 4)
                                }
                                .padding(.trailing, 20)
                                .padding(.bottom, 24) // Just above tab bar
                            }
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    periodSelector
                }
                ToolbarItem(placement: .topBarTrailing) {
                    accountSwitcher
                }
            }
            .onAppear { loadDashboardData() }
            .onChange(of: appState.selectedAccount) { _, _ in loadDashboardData() }
            .onChange(of: appState.showAllAccounts) { _, _ in loadDashboardData() }
            .onChange(of: appState.selectedConto) { _, _ in loadDashboardData() }
            .onChange(of: appState.showAllConti) { _, _ in loadDashboardData() }
            .onChange(of: appState.dataRefreshTrigger) { _, _ in loadDashboardData() }
        }
    }

    // MARK: - Sheet Content

    private var sheetContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if appState.showAllAccounts {
                    contiListContent
                } else {
                    recentTransactionsContent
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Gradient Background

    private var gradientBackground: some View {
        theme.dashboardGradient
            .ignoresSafeArea()
    }

    // MARK: - Balance Hero Section

    private var balanceHeroSection: some View {
        VStack(spacing: 6) {
            Text(totalBalance.currencyFormatted)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: isPositiveChange ? "arrow.up.right" : "arrow.down.right")
                        .font(.subheadline.weight(.semibold))

                    Text(String(format: "%+.2f%%", percentageChange))
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(isPositiveChange ? Color(hex: "#4CAF50") : Color(hex: "#FF5252"))

                Text(absoluteChange.currencyFormatted)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    // MARK: - Quick Actions Section

    private var quickActionsSection: some View {
        HStack(spacing: 0) {
            GlassCircleButton(icon: "plus", label: "Entrata") {
                appState.presentQuickTransaction(type: .income)
            }
            .frame(maxWidth: .infinity)

            GlassCircleButton(icon: "minus", label: "Uscita") {
                appState.presentQuickTransaction(type: .expense)
            }
            .frame(maxWidth: .infinity)

            GlassCircleButton(icon: "arrow.left.arrow.right", label: "Trasferimento") {
                appState.presentQuickTransaction(type: .transfer)
            }
            .frame(maxWidth: .infinity)

            Menu {
                Button {
                    appState.selectTab(.settings)
                } label: {
                    Label("Budget", systemImage: "chart.pie")
                }

                Button {
                    appState.selectTab(.settings)
                } label: {
                    Label("Categorie", systemImage: "tag")
                }

                Button {
                    appState.selectTab(.transactions)
                } label: {
                    Label("Report", systemImage: "chart.bar")
                }

                Button {
                    appState.selectTab(.settings)
                } label: {
                    Label("Impostazioni", systemImage: "gearshape")
                }
            } label: {
                VStack(spacing: 6) {
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 56, height: 56)
                        .overlay {
                            Circle()
                                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                        }
                        .overlay {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(.white)
                        }

                    Text("Altro")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Balance Chart Section

    // Determine if we should show multi-line chart
    private var shouldShowMultiLineChart: Bool {
        // Case 1: All Libri selected with multiple accounts
        if appState.showAllAccounts && displayedAccounts.count > 1 {
            return true
        }
        // Case 2: Single Libro selected with "all conti" and multiple conti
        if !appState.showAllAccounts && appState.showAllConti && allDisplayedConti.count > 1 {
            return true
        }
        return false
    }

    @ViewBuilder
    private func balanceChartSection(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if shouldShowMultiLineChart {
                if appState.showAllAccounts {
                    multiAccountChartView(height: height)
                } else {
                    multiContoChartView(height: height)
                }
            } else {
                singleAccountChartView(height: height)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: height)
    }

    private var periodSelector: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(ChartPeriod.allCases) { period in
                    Button {
                        selectedPeriod = period
                        if period == .oneMonth {
                            selectedMonth = Date() // Reset to current month
                        }
                        loadChartData()
                    } label: {
                        HStack {
                            Text(period.displayName)
                            if period == selectedPeriod {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selectedPeriod.rawValue)
                        .font(.subheadline.weight(.medium))
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(.white)
            }

            // Month picker when 1M is selected
            if selectedPeriod == .oneMonth {
                monthSelector
            }
        }
    }

    private var monthSelector: some View {
        Menu {
            ForEach(availableMonths, id: \.self) { month in
                Button {
                    selectedMonth = month
                    loadChartData()
                } label: {
                    HStack {
                        Text(monthYearFormatter.string(from: month))
                        if Calendar.current.isDate(month, equalTo: selectedMonth, toGranularity: .month) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(monthYearFormatter.string(from: selectedMonth))
                    .font(.subheadline.weight(.medium))
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .foregroundStyle(.white.opacity(0.8))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.1))
            .cornerRadius(8)
        }
    }

    private var availableMonths: [Date] {
        let calendar = Calendar.current
        let now = Date()
        var months: [Date] = []

        // Generate last 12 months
        for i in 0..<12 {
            if let month = calendar.date(byAdding: .month, value: -i, to: now) {
                let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: month))!
                months.append(startOfMonth)
            }
        }
        return months
    }

    private var monthYearFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        formatter.locale = Locale(identifier: "it_IT")
        return formatter
    }

    /// Returns the Y-axis domain based on actual data with some padding
    private var chartYDomain: ClosedRange<Decimal> {
        let allPoints = pastBalanceHistory + futureBalanceHistory
        guard !allPoints.isEmpty else { return 0...100 }

        let values = allPoints.map { $0.balance }
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 100

        // Add 10% padding above and below
        let range = maxValue - minValue
        let padding = range * Decimal(0.1)

        // Don't go below 0 for the minimum unless data is negative
        let lowerBound = minValue >= 0 ? max(0, minValue - padding) : minValue - padding
        let upperBound = maxValue + padding

        // Ensure there's always some range
        if lowerBound == upperBound {
            return (lowerBound - 50)...(upperBound + 50)
        }

        return lowerBound...upperBound
    }

    /// Returns the full date range for the chart X-axis
    private var chartDateRange: ClosedRange<Date> {
        let calendar = Calendar.current

        if selectedPeriod == .oneMonth {
            // Full month range for the selected month
            let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedMonth))!
            let endOfMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth)!
            return startOfMonth...endOfMonth
        } else {
            // For other periods, use the data range or calculate from period
            let now = Date()
            let monthsBack = selectedPeriod.monthsCount ?? 24
            let startDate = calendar.date(byAdding: .month, value: -monthsBack, to: now)!
            return startDate...now
        }
    }

    /// Balance history up to and including today (solid line)
    private var pastBalanceHistory: [BalanceDataPoint] {
        let calendar = Calendar.current
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))!
        return balanceHistory.filter { $0.date < endOfToday }
    }

    /// Balance history after today (dashed line for future/planned)
    private var futureBalanceHistory: [BalanceDataPoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: today)!

        // Get future points from balance history
        var future = balanceHistory.filter { $0.date >= endOfToday }

        // We need a connection point from the last past value
        guard let lastPast = pastBalanceHistory.last else {
            return future
        }

        // Always start future line from today's balance for continuity
        let todayPoint = BalanceDataPoint(date: today, balance: lastPast.balance)

        if future.isEmpty {
            // No future transactions - create projection to end of period
            if selectedPeriod == .oneMonth {
                let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedMonth))!
                let endOfMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth)!
                if endOfMonth > today {
                    return [todayPoint, BalanceDataPoint(date: endOfMonth, balance: lastPast.balance)]
                }
            }
            return []
        } else {
            // Has future transactions - connect from today
            future.insert(todayPoint, at: 0)

            // For 1M view, also extend to end of month if needed
            if selectedPeriod == .oneMonth {
                let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedMonth))!
                let endOfMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth)!
                if let lastFuture = future.last, lastFuture.date < endOfMonth {
                    future.append(BalanceDataPoint(date: endOfMonth, balance: lastFuture.balance))
                }
            }

            return future
        }
    }

    private func loadChartData() {
        let allContiIDs = Set(allDisplayedConti.map { $0.id })

        if appState.showAllAccounts && displayedAccounts.count > 1 {
            // Multiple Libri selected - show by Libro
            loadMultiAccountBalanceHistory()
        } else if !appState.showAllAccounts && appState.showAllConti && allDisplayedConti.count > 1 {
            // Single Libro with all conti - show by Conto
            loadMultiContoBalanceHistory()
        } else {
            // Single conto or aggregated view
            loadBalanceHistory(contiIDs: allContiIDs)
        }
    }

    @ViewBuilder
    private func singleAccountChartView(height: CGFloat) -> some View {
        if balanceHistory.isEmpty {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .frame(height: height)
                .overlay {
                    Text("Nessun dato disponibile")
                        .foregroundStyle(.white.opacity(0.5))
                }
        } else {
            Chart {
                // Past data - solid line
                ForEach(pastBalanceHistory, id: \.date) { item in
                    LineMark(
                        x: .value("Data", item.date, unit: selectedPeriod.useWeeklyAxis ? .day : .month),
                        y: .value("Saldo", item.balance),
                        series: .value("Serie", "Passato")
                    )
                    .foregroundStyle(theme.color)
                    .interpolationMethod(.stepEnd)
                    .lineStyle(StrokeStyle(lineWidth: 3))
                }

                // Future data - dashed line with lighter color
                ForEach(futureBalanceHistory, id: \.date) { item in
                    LineMark(
                        x: .value("Data", item.date, unit: selectedPeriod.useWeeklyAxis ? .day : .month),
                        y: .value("Saldo", item.balance),
                        series: .value("Serie", "Futuro")
                    )
                    .foregroundStyle(theme.color.opacity(0.5))
                    .interpolationMethod(.stepEnd)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [8, 4]))
                }
            }
            .chartXAxis {
                if selectedPeriod.useWeeklyAxis {
                    AxisMarks(values: .stride(by: .day, count: 7)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(.white.opacity(0.2))
                        AxisValueLabel(format: .dateTime.day())
                            .foregroundStyle(.white.opacity(0.6))
                    }
                } else {
                    AxisMarks(values: .stride(by: .month, count: selectedPeriod.axisStrideCount)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(.white.opacity(0.2))
                        AxisValueLabel(format: .dateTime.month(.abbreviated))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
            .chartYAxis(showYAxis ? .visible : .hidden)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisValueLabel {
                        if let decimal = value.as(Decimal.self) {
                            Text(formatCompactCurrency(decimal))
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                }
            }
            .chartXScale(domain: chartDateRange)
            .chartYScale(domain: chartYDomain)
            .chartPlotStyle { plotArea in
                plotArea
            }
            .frame(height: height)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showYAxis.toggle()
                }
            }
        }
    }


    @ViewBuilder
    private func multiAccountChartView(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if multiAccountHistory.isEmpty {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.05))
                    .frame(height: height)
                    .overlay {
                        Text("Nessun dato disponibile")
                            .foregroundStyle(.white.opacity(0.5))
                    }
            } else {
                Chart(multiAccountHistory) { item in
                    LineMark(
                        x: .value("Data", item.date, unit: selectedPeriod.useWeeklyAxis ? .day : .month),
                        y: .value("Saldo", item.balance)
                    )
                    .foregroundStyle(by: .value("Account", item.accountName))
                    .interpolationMethod(.stepEnd)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                }
                .chartXAxis {
                    if selectedPeriod.useWeeklyAxis {
                        AxisMarks(values: .stride(by: .day, count: 7)) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                .foregroundStyle(.white.opacity(0.2))
                            AxisValueLabel(format: .dateTime.day())
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    } else {
                        AxisMarks(values: .stride(by: .month, count: selectedPeriod.axisStrideCount)) { _ in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                .foregroundStyle(.white.opacity(0.2))
                            AxisValueLabel(format: .dateTime.month(.abbreviated))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                }
                .chartYAxis(showYAxis ? .visible : .hidden)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisValueLabel {
                            if let decimal = value.as(Decimal.self) {
                                Text(formatCompactCurrency(decimal))
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                        }
                    }
                }
                .chartForegroundStyleScale(domain: displayedAccounts.map { $0.name ?? "Account" },
                                           range: displayedAccounts.enumerated().map { colorForAccount(at: $0.offset) })
                .chartLegend(position: .bottom, alignment: .leading) {
                    HStack(spacing: 12) {
                        ForEach(Array(displayedAccounts.enumerated()), id: \.element.id) { index, account in
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(colorForAccount(at: index))
                                    .frame(width: 8, height: 8)
                                Text(account.name ?? "Account")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }
                    }
                }
                .chartXScale(domain: chartDateRange)
                .chartYScale(domain: chartYDomain)
                .chartPlotStyle { plotArea in
                    plotArea
                }
                .frame(height: height)
                .environment(\.colorScheme, .dark)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showYAxis.toggle()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func multiContoChartView(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if multiContoHistory.isEmpty {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.05))
                    .frame(height: height)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "chart.line.downtrend.xyaxis")
                                .font(.largeTitle)
                                .foregroundStyle(.white.opacity(0.3))
                            Text("Nessuna transazione nel periodo")
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
            } else {
                Chart(multiContoHistory) { item in
                    LineMark(
                        x: .value("Data", item.date, unit: selectedPeriod.useWeeklyAxis ? .day : .month),
                        y: .value("Saldo", item.balance)
                    )
                    .foregroundStyle(by: .value("Conto", item.accountName))
                    .interpolationMethod(.stepEnd)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                }
                .chartXAxis {
                    if selectedPeriod.useWeeklyAxis {
                        AxisMarks(values: .stride(by: .day, count: 7)) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                .foregroundStyle(.white.opacity(0.2))
                            AxisValueLabel(format: .dateTime.day())
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    } else {
                        AxisMarks(values: .stride(by: .month, count: selectedPeriod.axisStrideCount)) { _ in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                .foregroundStyle(.white.opacity(0.2))
                            AxisValueLabel(format: .dateTime.month(.abbreviated))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                }
                .chartYAxis(showYAxis ? .visible : .hidden)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisValueLabel {
                            if let decimal = value.as(Decimal.self) {
                                Text(formatCompactCurrency(decimal))
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                        }
                    }
                }
                .chartForegroundStyleScale(domain: allDisplayedConti.map { $0.name ?? "Conto" },
                                           range: allDisplayedConti.enumerated().map { colorForAccount(at: $0.offset) })
                .chartLegend(position: .bottom, alignment: .leading) {
                    HStack(spacing: 12) {
                        ForEach(Array(allDisplayedConti.enumerated()), id: \.element.id) { index, conto in
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(colorForAccount(at: index))
                                    .frame(width: 8, height: 8)
                                Text(conto.name ?? "Conto")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }
                    }
                }
                .chartXScale(domain: chartDateRange)
                .chartYScale(domain: chartYDomain)
                .chartPlotStyle { plotArea in
                    plotArea
                }
                .frame(height: height)
                .environment(\.colorScheme, .dark)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showYAxis.toggle()
                    }
                }
            }
        }
    }


    // MARK: - Account List Content

    private var contiListContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("I tuoi account")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.top, 20)
                .padding(.horizontal, 20)

            if allDisplayedConti.isEmpty {
                emptyStateView(icon: "creditcard", message: "Nessun account")
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(allDisplayedConti, id: \.id) { conto in
                        NavigationLink {
                            TransactionListView(initialConto: conto)
                        } label: {
                            CryptoContoRow(
                                conto: conto,
                                change: contiChanges[conto.id] ?? 0,
                                theme: theme,
                                showLibroName: true
                            )
                        }
                        .buttonStyle(.plain)

                        if conto.id != allDisplayedConti.last?.id {
                            Divider()
                                .background(Color.white.opacity(0.1))
                                .padding(.horizontal, 20)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Recent Transactions Content

    private var recentTransactionsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Ultime transazioni")
                    .font(.headline)
                    .foregroundStyle(.white)

                Spacer()

                Button {
                    appState.selectTab(.transactions)
                } label: {
                    Text("Vedi tutte")
                        .font(.subheadline)
                        .foregroundStyle(theme.color)
                }
            }
            .padding(.top, 20)
            .padding(.horizontal, 20)

            if recentTransactions.isEmpty {
                emptyStateView(icon: "list.bullet", message: "Nessuna transazione")
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(recentTransactions, id: \.id) { transaction in
                        CryptoTransactionRow(transaction: transaction, theme: theme)

                        if transaction.id != recentTransactions.last?.id {
                            Divider()
                                .background(Color.white.opacity(0.1))
                                .padding(.horizontal, 20)
                        }
                    }
                }
            }
        }
    }

    private func emptyStateView(icon: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(.white.opacity(0.4))

            Text(message)
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Libro & Account Switcher

    private var accountSwitcher: some View {
        Menu {
            // Tutti i Libri option
            Button {
                appState.selectAllAccounts()
            } label: {
                HStack {
                    Label("Tutti i Libri", systemImage: "square.stack.3d.up.fill")
                    if appState.showAllAccounts {
                        Image(systemName: "checkmark")
                    }
                }
            }

            Divider()

            // Individual Libri
            ForEach(activeAccounts, id: \.id) { libro in
                Menu {
                    // All accounts in this libro
                    Button {
                        appState.selectAccount(libro)
                        appState.selectAllConti()
                    } label: {
                        HStack {
                            Text("Tutti gli account")
                            if appState.selectedAccount?.id == libro.id && appState.showAllConti {
                                Image(systemName: "checkmark")
                            }
                        }
                    }

                    Divider()

                    // Individual accounts (conti) in this libro
                    ForEach(libro.activeConti, id: \.id) { conto in
                        Button {
                            appState.selectAccount(libro)
                            appState.selectConto(conto)
                        } label: {
                            HStack {
                                Label(conto.name ?? "Account", systemImage: conto.type?.icon ?? "creditcard")
                                if appState.selectedConto?.id == conto.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text(libro.name ?? "Libro")
                        if appState.selectedAccount?.id == libro.id && !appState.showAllAccounts {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                if appState.showAllAccounts {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.caption)
                }
                Text(displayName)
                    .font(.subheadline)
                Image(systemName: "chevron.down")
                    .font(.caption)
            }
            .foregroundStyle(.white)
        }
    }

    // MARK: - Formatting

    private func formatCompactCurrency(_ value: Decimal) -> String {
        let doubleValue = NSDecimalNumber(decimal: value).doubleValue
        let absValue = abs(doubleValue)

        if absValue >= 1_000_000 {
            return String(format: "%.1fM €", doubleValue / 1_000_000)
        } else if absValue >= 1_000 {
            return String(format: "%.0fK €", doubleValue / 1_000)
        } else {
            return String(format: "%.0f €", doubleValue)
        }
    }

    // MARK: - Data Loading

    private func loadDashboardData() {
        guard !displayedAccounts.isEmpty else {
            resetData()
            return
        }

        let allContiIDs = Set(allDisplayedConti.map { $0.id })
        let calendar = Calendar.current
        let now = Date()

        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth)!

        // Calculate previous month balance
        loadPreviousMonthBalance(contiIDs: allContiIDs, startOfMonth: startOfMonth)

        // Load monthly totals
        loadMonthlyTotals(contiIDs: allContiIDs, startOfMonth: startOfMonth, endOfMonth: endOfMonth)

        // Load balance history based on view mode
        if appState.showAllAccounts && displayedAccounts.count > 1 {
            // Multiple Libri - show by Libro
            loadMultiAccountBalanceHistory()
        } else if !appState.showAllAccounts && appState.showAllConti && allDisplayedConti.count > 1 {
            // Single Libro with all conti - show by Conto
            loadMultiContoBalanceHistory()
        } else {
            // Single conto or aggregated
            loadBalanceHistory(contiIDs: allContiIDs)
        }

        // Load conto changes
        loadContiChanges(startOfMonth: startOfMonth, endOfMonth: endOfMonth)

        // Load recent transactions (for single account view)
        if !appState.showAllAccounts {
            loadRecentTransactions(contiIDs: allContiIDs)
        }
    }

    private func resetData() {
        monthlyIncome = 0
        monthlyExpenses = 0
        previousMonthBalance = 0
        balanceHistory = []
        multiAccountHistory = []
        multiContoHistory = []
        contiChanges = [:]
        recentTransactions = []
        hasTransactionsInPeriod = true
    }

    private func loadPreviousMonthBalance(contiIDs: Set<UUID>, startOfMonth: Date) {
        var descriptor = FetchDescriptor<FinanceTransaction>()
        descriptor.predicate = #Predicate<FinanceTransaction> { transaction in
            transaction.date >= startOfMonth
        }

        do {
            let transactions = try modelContext.fetch(descriptor)

            let filtered = transactions.filter { transaction in
                if let id = transaction.fromContoId, contiIDs.contains(id) { return true }
                if let id = transaction.toContoId, contiIDs.contains(id) { return true }
                return false
            }

            let monthNet = filtered.reduce(Decimal(0)) { result, transaction in
                switch transaction.type {
                case .income:
                    return result + (transaction.amount ?? 0)
                case .expense:
                    return result - (transaction.amount ?? 0)
                case .transfer:
                    return result
                }
            }

            previousMonthBalance = totalBalance - monthNet
        } catch {
            previousMonthBalance = totalBalance
        }
    }

    private func loadMonthlyTotals(contiIDs: Set<UUID>, startOfMonth: Date, endOfMonth: Date) {
        var descriptor = FetchDescriptor<FinanceTransaction>()
        descriptor.predicate = #Predicate<FinanceTransaction> { transaction in
            transaction.date >= startOfMonth && transaction.date < endOfMonth
        }

        do {
            let transactions = try modelContext.fetch(descriptor)

            let filtered = transactions.filter { transaction in
                if let id = transaction.fromContoId, contiIDs.contains(id) { return true }
                if let id = transaction.toContoId, contiIDs.contains(id) { return true }
                return false
            }

            monthlyIncome = filtered
                .filter { $0.type == .income }
                .reduce(0) { $0 + ($1.amount ?? 0) }

            monthlyExpenses = filtered
                .filter { $0.type == .expense }
                .reduce(0) { $0 + ($1.amount ?? 0) }
        } catch {
            monthlyIncome = 0
            monthlyExpenses = 0
        }
    }

    private func loadBalanceHistory(contiIDs: Set<UUID>) {
        let calendar = Calendar.current
        let now = Date()

        // Get initial balance for selected conti
        let initialBalance: Decimal = allDisplayedConti.reduce(Decimal(0)) { $0 + ($1.initialBalance ?? 0) }

        // Determine date range based on selected period
        let periodStartDate: Date
        let periodEndDate: Date

        if selectedPeriod == .oneMonth {
            // Use the selected specific month - include future transactions too
            periodStartDate = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedMonth))!
            let endOfSelectedMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: periodStartDate)!
            periodEndDate = endOfSelectedMonth // Include full month with future transactions
        } else {
            // Calculate from current date
            let monthsToLoad = selectedPeriod.monthsCount ?? 24
            guard let start = calendar.date(byAdding: .month, value: -monthsToLoad, to: now) else {
                balanceHistory = []
                return
            }
            periodStartDate = start
            periodEndDate = now
        }

        guard periodStartDate <= periodEndDate else {
            balanceHistory = []
            return
        }

        // Fetch all transactions for these conti, sorted by date
        let descriptor = FetchDescriptor<FinanceTransaction>(
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )

        do {
            let allTransactions = try modelContext.fetch(descriptor)

            // Filter to only transactions for our conti
            let relevantTransactions = allTransactions.filter { transaction in
                if let id = transaction.fromContoId, contiIDs.contains(id) { return true }
                if let id = transaction.toContoId, contiIDs.contains(id) { return true }
                return false
            }

            // Calculate balance BEFORE the period start
            var balanceBeforePeriod = initialBalance
            for transaction in relevantTransactions {
                let transactionDate = transaction.date
                guard transactionDate < periodStartDate else { continue }

                let amount = transaction.amount ?? 0
                switch transaction.type {
                case .income:
                    if let toId = transaction.toContoId, contiIDs.contains(toId) {
                        balanceBeforePeriod += amount
                    }
                case .expense:
                    if let fromId = transaction.fromContoId, contiIDs.contains(fromId) {
                        balanceBeforePeriod -= amount
                    }
                case .transfer:
                    if let fromId = transaction.fromContoId, contiIDs.contains(fromId) {
                        balanceBeforePeriod -= amount
                    }
                    if let toId = transaction.toContoId, contiIDs.contains(toId) {
                        balanceBeforePeriod += amount
                    }
                }
            }

            // Filter transactions within the period
            let periodTransactions = relevantTransactions.filter { transaction in
                transaction.date >= periodStartDate && transaction.date <= periodEndDate
            }

            // Build balance history with monthly anchor points + transaction points
            var data: [BalanceDataPoint] = []
            var runningBalance = balanceBeforePeriod

            // Generate month end dates for the period
            var monthEndDates: [Date] = []
            var currentMonth = periodStartDate
            while currentMonth <= periodEndDate {
                // Get end of this month (or periodEndDate if it's the last month)
                let endOfMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: calendar.date(from: calendar.dateComponents([.year, .month], from: currentMonth))!)!
                let effectiveEnd = min(endOfMonth, periodEndDate)
                monthEndDates.append(effectiveEnd)

                guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) else { break }
                currentMonth = nextMonth
            }

            // Start with a point at the beginning of the period
            data.append(BalanceDataPoint(date: periodStartDate, balance: runningBalance))

            // Group transactions by day and calculate daily ending balances
            var transactionsByDay: [Date: [FinanceTransaction]] = [:]
            for transaction in periodTransactions {
                let dayStart = calendar.startOfDay(for: transaction.date)
                transactionsByDay[dayStart, default: []].append(transaction)
            }

            // Get sorted unique days with transactions
            let sortedDays = transactionsByDay.keys.sorted()

            // Process each day's transactions
            for day in sortedDays {
                guard let dayTransactions = transactionsByDay[day] else { continue }

                // Apply all transactions for this day
                for transaction in dayTransactions {
                    let amount = transaction.amount ?? 0
                    switch transaction.type {
                    case .income:
                        if let toId = transaction.toContoId, contiIDs.contains(toId) {
                            runningBalance += amount
                        }
                    case .expense:
                        if let fromId = transaction.fromContoId, contiIDs.contains(fromId) {
                            runningBalance -= amount
                        }
                    case .transfer:
                        if let fromId = transaction.fromContoId, contiIDs.contains(fromId) {
                            runningBalance -= amount
                        }
                        if let toId = transaction.toContoId, contiIDs.contains(toId) {
                            runningBalance += amount
                        }
                    }
                }

                // Add single data point for this day with final balance
                data.append(BalanceDataPoint(date: day, balance: runningBalance))
            }

            // Add month-end anchor points for months without transactions
            for monthEnd in monthEndDates {
                if let lastPoint = data.last, !calendar.isDate(lastPoint.date, inSameDayAs: monthEnd) {
                    // Check if we already have a point after the start of this month
                    let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: monthEnd))!
                    let hasPointInMonth = data.contains { calendar.isDate($0.date, equalTo: monthEnd, toGranularity: .month) }
                    if !hasPointInMonth || data.last!.date < monthEnd {
                        data.append(BalanceDataPoint(date: monthEnd, balance: runningBalance))
                    }
                }
            }

            // Sort data by date to ensure correct order
            balanceHistory = data.sorted { $0.date < $1.date }
        } catch {
            balanceHistory = []
        }
    }

    private func loadMultiAccountBalanceHistory() {
        let calendar = Calendar.current
        let now = Date()
        var data: [AccountBalanceDataPoint] = []

        // Determine number of months based on selected period
        let monthsToLoad = selectedPeriod.monthsCount ?? 24

        for (accountIndex, account) in displayedAccounts.enumerated() {
            let contiIDs = Set(account.activeConti.map { $0.id })
            let color = colorForAccount(at: accountIndex)
            let accountName = account.name ?? "Account"

            // Calculate balance as of today (excluding future transactions)
            var balanceAsOfToday: Decimal = account.activeConti.reduce(Decimal(0)) { $0 + ($1.initialBalance ?? 0) }

            var todayDescriptor = FetchDescriptor<FinanceTransaction>()
            todayDescriptor.predicate = #Predicate<FinanceTransaction> { transaction in
                transaction.date <= now
            }

            do {
                let allTransactions = try modelContext.fetch(todayDescriptor)
                let relevantTransactions = allTransactions.filter { transaction in
                    if let id = transaction.fromContoId, contiIDs.contains(id) { return true }
                    if let id = transaction.toContoId, contiIDs.contains(id) { return true }
                    return false
                }

                for transaction in relevantTransactions {
                    let amount = transaction.amount ?? 0
                    switch transaction.type {
                    case .income:
                        if let toId = transaction.toContoId, contiIDs.contains(toId) {
                            balanceAsOfToday += amount
                        }
                    case .expense:
                        if let fromId = transaction.fromContoId, contiIDs.contains(fromId) {
                            balanceAsOfToday -= amount
                        }
                    case .transfer:
                        // Internal transfers within same account net to zero
                        if let fromId = transaction.fromContoId, contiIDs.contains(fromId) {
                            balanceAsOfToday -= amount
                        }
                        if let toId = transaction.toContoId, contiIDs.contains(toId) {
                            balanceAsOfToday += amount
                        }
                    }
                }
            } catch {
                balanceAsOfToday = account.totalBalance
            }

            // Collect monthly net changes for this account
            var monthlyNetChanges: [(date: Date, net: Decimal)] = []

            for i in 0..<monthsToLoad {
                guard let monthDate = calendar.date(byAdding: .month, value: -i, to: now) else { continue }

                let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: monthDate))!
                let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth)!
                let effectiveEndDate = i == 0 ? now : endOfMonth

                var descriptor = FetchDescriptor<FinanceTransaction>()
                descriptor.predicate = #Predicate<FinanceTransaction> { transaction in
                    transaction.date >= startOfMonth && transaction.date <= effectiveEndDate
                }

                do {
                    let transactions = try modelContext.fetch(descriptor)

                    let filtered = transactions.filter { transaction in
                        if let id = transaction.fromContoId, contiIDs.contains(id) { return true }
                        if let id = transaction.toContoId, contiIDs.contains(id) { return true }
                        return false
                    }

                    var netChange: Decimal = 0
                    for transaction in filtered {
                        let amount = transaction.amount ?? 0
                        switch transaction.type {
                        case .income:
                            if let toId = transaction.toContoId, contiIDs.contains(toId) {
                                netChange += amount
                            }
                        case .expense:
                            if let fromId = transaction.fromContoId, contiIDs.contains(fromId) {
                                netChange -= amount
                            }
                        case .transfer:
                            if let fromId = transaction.fromContoId, contiIDs.contains(fromId) {
                                netChange -= amount
                            }
                            if let toId = transaction.toContoId, contiIDs.contains(toId) {
                                netChange += amount
                            }
                        }
                    }

                    monthlyNetChanges.append((date: startOfMonth, net: netChange))
                } catch {
                    monthlyNetChanges.append((date: startOfMonth, net: 0))
                }
            }

            // Build balance history by working backwards
            var accountData: [AccountBalanceDataPoint] = []
            var runningBalance = balanceAsOfToday

            for (index, monthData) in monthlyNetChanges.enumerated() {
                if index == 0 {
                    accountData.append(AccountBalanceDataPoint(
                        accountId: account.id,
                        accountName: accountName,
                        date: monthData.date,
                        balance: runningBalance,
                        color: color
                    ))
                } else {
                    let recentMonthNet = monthlyNetChanges[index - 1].net
                    runningBalance -= recentMonthNet
                    accountData.append(AccountBalanceDataPoint(
                        accountId: account.id,
                        accountName: accountName,
                        date: monthData.date,
                        balance: runningBalance,
                        color: color
                    ))
                }
            }

            // Add reversed data (oldest first) for this account
            data.append(contentsOf: accountData.reversed())
        }

        multiAccountHistory = data
    }

    private func loadMultiContoBalanceHistory() {
        let calendar = Calendar.current
        let now = Date()
        var data: [AccountBalanceDataPoint] = []

        // Determine number of months based on selected period
        let monthsToLoad = selectedPeriod.monthsCount ?? 24

        for (contoIndex, conto) in allDisplayedConti.enumerated() {
            let contoID = conto.id
            let color = colorForAccount(at: contoIndex)
            let contoName = conto.name ?? "Conto"

            // Calculate balance as of today (excluding future transactions)
            var balanceAsOfToday = conto.initialBalance ?? 0

            var todayDescriptor = FetchDescriptor<FinanceTransaction>()
            todayDescriptor.predicate = #Predicate<FinanceTransaction> { transaction in
                transaction.date <= now
            }

            do {
                let allTransactions = try modelContext.fetch(todayDescriptor)
                let relevantTransactions = allTransactions.filter { transaction in
                    transaction.fromContoId == contoID || transaction.toContoId == contoID
                }

                for transaction in relevantTransactions {
                    let amount = transaction.amount ?? 0
                    switch transaction.type {
                    case .income:
                        if transaction.toContoId == contoID {
                            balanceAsOfToday += amount
                        }
                    case .expense:
                        if transaction.fromContoId == contoID {
                            balanceAsOfToday -= amount
                        }
                    case .transfer:
                        if transaction.fromContoId == contoID {
                            balanceAsOfToday -= amount
                        }
                        if transaction.toContoId == contoID {
                            balanceAsOfToday += amount
                        }
                    }
                }
            } catch {
                balanceAsOfToday = conto.balance
            }

            // Collect monthly net changes for this conto
            var monthlyNetChanges: [(date: Date, net: Decimal)] = []
            var hasAnyTransactions = false

            for i in 0..<monthsToLoad {
                guard let monthDate = calendar.date(byAdding: .month, value: -i, to: now) else { continue }

                let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: monthDate))!
                let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth)!
                let effectiveEndDate = i == 0 ? now : endOfMonth

                var descriptor = FetchDescriptor<FinanceTransaction>()
                descriptor.predicate = #Predicate<FinanceTransaction> { transaction in
                    transaction.date >= startOfMonth && transaction.date <= effectiveEndDate
                }

                do {
                    let transactions = try modelContext.fetch(descriptor)

                    let filtered = transactions.filter { transaction in
                        transaction.fromContoId == contoID || transaction.toContoId == contoID
                    }

                    if !filtered.isEmpty {
                        hasAnyTransactions = true
                    }

                    var netChange: Decimal = 0
                    for transaction in filtered {
                        let amount = transaction.amount ?? 0
                        switch transaction.type {
                        case .income:
                            if transaction.toContoId == contoID {
                                netChange += amount
                            }
                        case .expense:
                            if transaction.fromContoId == contoID {
                                netChange -= amount
                            }
                        case .transfer:
                            if transaction.fromContoId == contoID {
                                netChange -= amount
                            }
                            if transaction.toContoId == contoID {
                                netChange += amount
                            }
                        }
                    }

                    monthlyNetChanges.append((date: startOfMonth, net: netChange))
                } catch {
                    monthlyNetChanges.append((date: startOfMonth, net: 0))
                }
            }

            // Only add this conto if it has transactions
            guard hasAnyTransactions else { continue }

            // Build balance history by working backwards
            var contoData: [AccountBalanceDataPoint] = []
            var runningBalance = balanceAsOfToday

            for (index, monthData) in monthlyNetChanges.enumerated() {
                if index == 0 {
                    contoData.append(AccountBalanceDataPoint(
                        accountId: contoID,
                        accountName: contoName,
                        date: monthData.date,
                        balance: runningBalance,
                        color: color
                    ))
                } else {
                    let recentMonthNet = monthlyNetChanges[index - 1].net
                    runningBalance -= recentMonthNet
                    contoData.append(AccountBalanceDataPoint(
                        accountId: contoID,
                        accountName: contoName,
                        date: monthData.date,
                        balance: runningBalance,
                        color: color
                    ))
                }
            }

            // Add reversed data (oldest first) for this conto
            data.append(contentsOf: contoData.reversed())
        }

        multiContoHistory = data
    }

    private func loadContiChanges(startOfMonth: Date, endOfMonth: Date) {
        var changes: [UUID: Decimal] = [:]

        for conto in allDisplayedConti {
            var descriptor = FetchDescriptor<FinanceTransaction>()
            descriptor.predicate = #Predicate<FinanceTransaction> { transaction in
                transaction.date >= startOfMonth && transaction.date < endOfMonth
            }

            do {
                let transactions = try modelContext.fetch(descriptor)

                let contoTransactions = transactions.filter { transaction in
                    transaction.fromContoId == conto.id || transaction.toContoId == conto.id
                }

                let change = contoTransactions.reduce(Decimal(0)) { result, transaction in
                    switch transaction.type {
                    case .income:
                        if transaction.toContoId == conto.id {
                            return result + (transaction.amount ?? 0)
                        }
                        return result
                    case .expense:
                        if transaction.fromContoId == conto.id {
                            return result - (transaction.amount ?? 0)
                        }
                        return result
                    case .transfer:
                        if transaction.fromContoId == conto.id {
                            return result - (transaction.amount ?? 0)
                        } else if transaction.toContoId == conto.id {
                            return result + (transaction.amount ?? 0)
                        }
                        return result
                    }
                }

                changes[conto.id] = change
            } catch {
                changes[conto.id] = 0
            }
        }

        contiChanges = changes
    }

    private func loadRecentTransactions(contiIDs: Set<UUID>) {
        // Fetch more transactions to ensure we find enough for the selected conto
        let descriptor = FetchDescriptor<FinanceTransaction>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        // Don't limit the fetch - filter first, then take the most recent 10

        do {
            let allTransactions = try modelContext.fetch(descriptor)

            // Filter by selected conti and take only the first 10
            recentTransactions = Array(
                allTransactions
                    .filter { transaction in
                        if let id = transaction.fromContoId, contiIDs.contains(id) { return true }
                        if let id = transaction.toContoId, contiIDs.contains(id) { return true }
                        return false
                    }
                    .prefix(10)
            )
        } catch {
            recentTransactions = []
        }
    }
}

// MARK: - Crypto Transaction Row

struct CryptoTransactionRow: View {
    let transaction: FinanceTransaction
    let theme: AppTheme

    private var isIncome: Bool { transaction.type == .income }
    private var isTransfer: Bool { transaction.type == .transfer }

    private var iconName: String {
        if isTransfer {
            return "arrow.left.arrow.right"
        }
        return transaction.category?.icon ?? (isIncome ? "arrow.down.circle" : "arrow.up.circle")
    }

    private var iconColor: Color {
        if isTransfer {
            return .blue
        }
        if let colorHex = transaction.category?.color {
            return Color(hex: colorHex)
        }
        return isIncome ? Color(hex: "#4CAF50") : Color(hex: "#FF5252")
    }

    private var amountColor: Color {
        if isTransfer {
            return .white
        }
        return isIncome ? Color(hex: "#4CAF50") : Color(hex: "#FF5252")
    }

    private var amountPrefix: String {
        if isTransfer { return "" }
        return isIncome ? "+" : "-"
    }

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Circle()
                .fill(iconColor.opacity(0.2))
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: iconName)
                        .font(.system(size: 18))
                        .foregroundStyle(iconColor)
                }

            // Description and category
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.transactionDescription ?? "Transazione")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(transaction.category?.name ?? transaction.type.displayName)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer()

            // Amount and date
            VStack(alignment: .trailing, spacing: 2) {
                Text(amountPrefix + (transaction.amount ?? 0).currencyFormatted)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(amountColor)

                Text(transaction.date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

// MARK: - Crypto Conto Row

struct CryptoContoRow: View {
    let conto: Conto
    let change: Decimal
    let theme: AppTheme
    var showLibroName: Bool = false

    private var isPositiveChange: Bool { change >= 0 }

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Circle()
                .fill(theme.color.opacity(0.2))
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: conto.type?.icon ?? "creditcard")
                        .font(.system(size: 18))
                        .foregroundStyle(theme.color)
                }

            // Name and libro
            VStack(alignment: .leading, spacing: 2) {
                Text(conto.name ?? "Account")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)

                if showLibroName, let libroName = conto.account?.name {
                    Text(libroName)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                } else {
                    Text(conto.type?.displayName ?? "")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            Spacer()

            // Balance and change
            VStack(alignment: .trailing, spacing: 2) {
                Text(conto.balance.currencyFormatted)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                if change != 0 {
                    Text((isPositiveChange ? "+" : "") + change.currencyFormatted)
                        .font(.caption)
                        .foregroundStyle(isPositiveChange ? Color(hex: "#4CAF50") : Color(hex: "#FF5252"))
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

// MARK: - Preview

#Preview {
    CryptoDashboardView()
        .environment(AppStateManager())
        .modelContainer(try! FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true))
}
