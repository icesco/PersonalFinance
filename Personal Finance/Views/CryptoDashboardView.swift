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

// ChartPeriod and AccountBalanceDataPoint are now in FinanceCore

struct CryptoDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStateManager.self) private var appState

    @Query private var allAccounts: [Account]

    // ViewModel for all data/business logic
    @State private var viewModel = DashboardViewModel()

    @State private var transactionToEdit: FinanceTransaction?
    @State private var transactionToDetail: FinanceTransaction?

    // Sheet detent tracking
    @State private var selectedDetent: SheetDetent = .height(280)
    @State private var currentSheetHeight: CGFloat = 280  // Real-time height during drag
    @State private var isSheetDismissed: Bool = false  // When true, sheet is hidden and FAB is shown

    // Chart Y-axis visibility (toggle on tap)
    @State private var showYAxis: Bool = false

    // Dashboard page index (0 = chart, 1 = analytics)
    @State private var dashboardPage: Int = 0

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

    // Computed properties — use allDisplayedConti so the balance updates
    // when switching between "all conti" and a single conto.
    // Uses balance (not displayBalance) so the total reflects real liquidity,
    // not credit card plafond which isn't the user's money.
    private var totalBalance: Decimal {
        allDisplayedConti.reduce(Decimal(0)) { $0 + $1.balance }
    }

    private var absoluteChange: Decimal {
        viewModel.absoluteChange(currentTotal: totalBalance)
    }

    private var percentageChange: Double {
        viewModel.percentageChange(currentTotal: totalBalance)
    }

    private var isPositiveChange: Bool {
        absoluteChange >= 0
    }

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

                        // Balance Chart / Analytics - fills remaining space to sheet
                        dashboardPageView(height: dynamicChartHeight)
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
            .sheet(item: $transactionToEdit) { transaction in
                EditTransactionView(transaction: transaction)
            }
            .sheet(item: $transactionToDetail) { transaction in
                NavigationStack {
                    TransactionDetailView(transaction: transaction)
                }
            }
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
        AnimatedMeshGradient(baseColor: theme.color)
            .ignoresSafeArea()
    }

    // MARK: - Balance Hero Section

    private var balanceHeroSection: some View {
        VStack(spacing: 6) {
            Text(totalBalance.currencyFormatted)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            HStack(spacing: 8) {
                // Percentage change with pill background for visibility
                HStack(spacing: 4) {
                    Image(systemName: isPositiveChange ? "arrow.up.right" : "arrow.down.right")
                        .font(.caption.weight(.bold))

                    Text(String(format: "%.1f%%", abs(percentageChange)))
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(isPositiveChange ? Color(hex: "#4CAF50") : Color(hex: "#FF5252"))
                )

                // Absolute change
                Text((isPositiveChange ? "+" : "") + absoluteChange.currencyFormatted)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.8))
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

    // MARK: - Dashboard Page View (Chart + Analytics)

    @ViewBuilder
    private func dashboardPageView(height: CGFloat) -> some View {
        TabView(selection: $dashboardPage) {
            balanceChartSection(height: height)
                .tag(0)

            AnalyticsWidgetsPage(
                viewModel: viewModel,
                theme: theme,
                height: height
            )
            .tag(1)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .frame(height: height)
        .onAppear {
            // White page dots on dark background
            UIPageControl.appearance().currentPageIndicatorTintColor = .white
            UIPageControl.appearance().pageIndicatorTintColor = UIColor.white.withAlphaComponent(0.3)
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
                        viewModel.selectedPeriod = period
                        if period == .oneMonth {
                            viewModel.selectedMonth = Date()
                        }
                        loadChartData()
                    } label: {
                        HStack {
                            Text(period.displayName)
                            if period == viewModel.selectedPeriod {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(viewModel.selectedPeriod.rawValue)
                        .font(.subheadline.weight(.medium))
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(.white)
            }

            // Month picker when 1M is selected
            if viewModel.selectedPeriod == .oneMonth {
                monthSelector
            }
        }
    }

    private var monthSelector: some View {
        Menu {
            ForEach(availableMonths, id: \.self) { month in
                Button {
                    viewModel.selectedMonth = month
                    loadChartData()
                } label: {
                    HStack {
                        Text(monthYearFormatter.string(from: month))
                        if Calendar.current.isDate(month, equalTo: viewModel.selectedMonth, toGranularity: .month) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(monthYearFormatter.string(from: viewModel.selectedMonth))
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

    private var chartYDomain: ClosedRange<Decimal> {
        viewModel.chartYDomain(for: displayedAccounts)
    }

    /// Returns the full date range for the chart X-axis
    private var chartDateRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let now = Date()

        if viewModel.selectedPeriod == .oneMonth {
            let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: viewModel.selectedMonth))!
            let endOfMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth)!
            return startOfMonth...endOfMonth
        } else {
            let monthsBack = viewModel.selectedPeriod.monthsCount ?? 24
            let startOfCurrentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
            let startDate = calendar.date(byAdding: .month, value: -(monthsBack - 1), to: startOfCurrentMonth)!
            return startDate...now
        }
    }

    private var pastBalanceHistory: [BalanceDataPoint] {
        viewModel.pastBalanceHistory(for: displayedAccounts)
    }

    private var futureBalanceHistory: [BalanceDataPoint] {
        viewModel.futureBalanceHistory(for: displayedAccounts)
    }

    private func loadChartData() {
        loadDashboardData()
    }

    @ViewBuilder
    private func singleAccountChartView(height: CGFloat) -> some View {
        if viewModel.balanceHistory.isEmpty {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .frame(height: height)
                .overlay {
                    Text("Nessun dato disponibile")
                        .foregroundStyle(.white.opacity(0.5))
                }
        } else {
            Chart {
                // Past data - solid white line
                ForEach(pastBalanceHistory, id: \.date) { item in
                    LineMark(
                        x: .value("Data", item.date, unit: .day),
                        y: .value("Saldo", item.balance),
                        series: .value("Serie", "Passato")
                    )
                    .foregroundStyle(.white)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 3))
                }

                // Future data - dashed white line with lower opacity
                ForEach(futureBalanceHistory, id: \.date) { item in
                    LineMark(
                        x: .value("Data", item.date, unit: .day),
                        y: .value("Saldo", item.balance),
                        series: .value("Serie", "Futuro")
                    )
                    .foregroundStyle(.white.opacity(0.5))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [8, 4]))
                }
            }
            .chartXAxis {
                if viewModel.selectedPeriod.useWeeklyAxis {
                    AxisMarks(values: .stride(by: .day, count: 7)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(.white.opacity(0.2))
                        AxisValueLabel(format: .dateTime.day())
                            .foregroundStyle(.white.opacity(0.6))
                    }
                } else {
                    AxisMarks(values: .stride(by: .month, count: viewModel.selectedPeriod.axisStrideCount)) { _ in
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
                            Text(BalanceCalculator.formatCompactCurrency(decimal))
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
            if viewModel.multiAccountHistory.isEmpty {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.05))
                    .frame(height: height)
                    .overlay {
                        Text("Nessun dato disponibile")
                            .foregroundStyle(.white.opacity(0.5))
                    }
            } else {
                Chart(viewModel.multiAccountHistory) { item in
                    LineMark(
                        x: .value("Data", item.date, unit: .day),
                        y: .value("Saldo", item.balance)
                    )
                    .foregroundStyle(by: .value("Account", item.accountName))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                }
                .chartXAxis {
                    if viewModel.selectedPeriod.useWeeklyAxis {
                        AxisMarks(values: .stride(by: .day, count: 7)) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                .foregroundStyle(.white.opacity(0.2))
                            AxisValueLabel(format: .dateTime.day())
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    } else {
                        AxisMarks(values: .stride(by: .month, count: viewModel.selectedPeriod.axisStrideCount)) { _ in
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
                                Text(BalanceCalculator.formatCompactCurrency(decimal))
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
            if viewModel.multiContoHistory.isEmpty {
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
                Chart(viewModel.multiContoHistory) { item in
                    LineMark(
                        x: .value("Data", item.date, unit: .day),
                        y: .value("Saldo", item.balance)
                    )
                    .foregroundStyle(by: .value("Conto", item.accountName))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                }
                .chartXAxis {
                    if viewModel.selectedPeriod.useWeeklyAxis {
                        AxisMarks(values: .stride(by: .day, count: 7)) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                .foregroundStyle(.white.opacity(0.2))
                            AxisValueLabel(format: .dateTime.day())
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    } else {
                        AxisMarks(values: .stride(by: .month, count: viewModel.selectedPeriod.axisStrideCount)) { _ in
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
                                Text(BalanceCalculator.formatCompactCurrency(decimal))
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
                                change: viewModel.contiChanges[conto.id] ?? 0,
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

            if viewModel.recentTransactions.isEmpty {
                emptyStateView(icon: "list.bullet", message: "Nessuna transazione")
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.recentTransactions, id: \.id) { transaction in
                        CryptoTransactionRow(transaction: transaction, theme: theme)
                            .contentShape(Rectangle())
                            .onTapGesture { transactionToDetail = transaction }
                            .contextMenu {
                                Button {
                                    transactionToDetail = transaction
                                } label: {
                                    Label("Dettagli", systemImage: "info.circle")
                                }
                                Button {
                                    transactionToEdit = transaction
                                } label: {
                                    Label("Modifica", systemImage: "pencil")
                                }
                            }

                        if transaction.id != viewModel.recentTransactions.last?.id {
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

    // MARK: - Data Loading

    private func loadDashboardData() {
        viewModel.loadDashboardData(
            displayedAccounts: displayedAccounts,
            allDisplayedConti: allDisplayedConti,
            showAllAccounts: appState.showAllAccounts,
            showAllConti: appState.showAllConti,
            modelContext: modelContext
        )
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
                Text(conto.displayBalance.currencyFormatted)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                if change != 0 {
                    Text((isPositiveChange ? "+" : "") + change.currencyFormatted)
                        .font(.caption)
                        .foregroundStyle(isPositiveChange ? Color(hex: "#4CAF50") : Color(hex: "#FF5252"))
                }

                ContoTypeSpecificInfoView(conto: conto, compact: true)
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
