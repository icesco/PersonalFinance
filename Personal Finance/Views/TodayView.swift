import SwiftUI
import SwiftData
import FinanceCore
import CoreData

/// The daily entry point: one estimate, its inputs, and the changes worth checking.
struct TodayView: View {
    enum Screen { case home, analysis }

    @Environment(AppStateManager.self) private var appState
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var reader = TodaySnapshotReader()
    @State private var snapshot: TodaySnapshot?
    @State private var loadedScope: Scope?
    @State private var refreshRevision = 0
    @State private var loadFailed = false
    @State private var lastSuccessfulLoad: Date?

    #if DEBUG
    var loadSnapshotForTesting: ((ModelContainer, UUID?, Bool) async throws -> TodaySnapshot)? = nil
    #endif

    var screen: Screen = .home

    @State private var showingImport = false
    @State private var showingBudgets = false
    @State private var showingBalances = false

    private struct Scope: Equatable {
        let accountID: UUID?
        let showAll: Bool
    }

    private struct Refresh: Equatable {
        let scope: Scope
        let revision: Int
    }

    private var scope: Scope {
        Scope(accountID: appState.selectedAccount?.id, showAll: appState.showAllAccounts)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let snapshot, loadedScope == scope {
                    if screen == .analysis {
                        if snapshot.hasMixedCurrencies {
                            ContentUnavailableView {
                                Label("Seleziona un solo libro", systemImage: "chart.pie")
                            } description: {
                                Text("L'analisi richiede movimenti nella stessa valuta.")
                            } actions: {
                                Button("Scegli libro nelle Impostazioni") { appState.openBookSettings() }
                                    .buttonStyle(.borderedProminent)
                                NavigationLink("Saldo storico per libro") { BalanceHistoryView() }
                            }
                            .themedBackground(tint: ForgiaPalette.margin)
                        } else {
                            SpendingOverviewView(transactions: snapshot.entries, currency: snapshot.currency, scopeContoIDs: snapshot.contoIDs,
                                                 initialBookID: appState.showAllAccounts ? nil : appState.selectedAccount?.id)
                        }
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                header(snapshot: snapshot)
                                CaptureInboxEntry(compactHomeStyle: true)
                                    .buttonStyle(.plain)
                                TodayMarginCard(
                                    snapshot: snapshot,
                                    onVerify: { showingBalances = true },
                                    onImport: { showingImport = true },
                                    onAddIncome: { appState.presentQuickTransaction(type: .income, planned: true) }
                                )
                                if horizontalSizeClass == .compact {
                                    TodaySectionCards()
                                }
                                if appState.selectedAccount != nil {
                                    TodayBudgetsCard(budgets: snapshot.budgets) {
                                        showingBudgets = true
                                    }
                                }
                                if !snapshot.hasMixedCurrencies {
                                    TodayActivityLayout(snapshot: snapshot)
                                    FinanceCalendarPreview(contoIDs: snapshot.contoIDs, currency: snapshot.currency,
                                                           upcoming: snapshot.planned.sorted { $0.date < $1.date })
                                    SpendingCommitmentSummary(direction: snapshot.direction, currency: snapshot.currency, scopeContoIDs: snapshot.contoIDs)
                                }
                            }
                            #if os(macOS)
                            .frame(maxWidth: 1040)
                            .frame(maxWidth: .infinity)
                            #endif
                            .padding(.horizontal, 22)
                            .padding(.top, 14)
                            .padding(.bottom, 32)
                            // Sub-point rounding in wrapped text must never widen the page into a sideways scroll.
                            .containerRelativeFrame(.horizontal)
                        }
                        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                        .themedBackground(tint: ForgiaPalette.margin)
                    }
                } else if loadFailed {
                    ContentUnavailableView {
                        Label("Riepilogo non disponibile", systemImage: "exclamationmark.triangle")
                    } actions: {
                        Button("Riprova") { refreshRevision &+= 1 }
                    }
                } else {
                    ProgressView("Caricamento riepilogo…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            #if os(iOS)
            .toolbar(screen == .home ? .hidden : .automatic, for: .navigationBar)
            .safeAreaBar(edge: .top, spacing: 0) {
                if screen == .home {
                    HStack(spacing: 10) {
                        FormiLogo(size: 28)
                            .accessibilityHidden(true)
                        Text("Oggi")
                            .font(.system(.title2, design: .serif, weight: .semibold))
                        Spacer()
                        CompactSettingsButton()
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 4)
                }
            }
            #endif
            .safeAreaInset(edge: .top, spacing: 0) {
                if loadFailed, snapshot != nil, loadedScope == scope {
                    TodayRefreshFailureBanner(lastSuccessfulLoad: lastSuccessfulLoad) {
                        refreshRevision &+= 1
                    }
                }
            }
            .transactionButtonRoot(screen == .analysis ? .analysis : .dashboard, isActive: screen != .analysis)
            .financePresentation(isPresented: $showingImport, title: "Importa CSV", width: 800) { CSVImportView() }
            .financePresentation(isPresented: $showingBudgets, title: "Budget", width: 800) { BudgetView() }
            .financePresentation(isPresented: $showingBalances, title: "Verifica saldi") {
                if let account = appState.selectedAccount {
                    BalanceReconciliationView(account: account)
                }
            }
        }
        .task(id: Refresh(scope: scope, revision: refreshRevision)) {
            let requestedScope = scope
            do {
                // Coalesce bursts of imports/saves; cancellation discards obsolete results.
                try await Task.sleep(for: .milliseconds(200))
                #if DEBUG
                let value: TodaySnapshot
                if let loadSnapshotForTesting {
                    value = try await loadSnapshotForTesting(context.container, requestedScope.accountID, requestedScope.showAll)
                } else {
                    value = try await reader.load(container: context.container, accountID: requestedScope.accountID, showAllAccounts: requestedScope.showAll)
                }
                #else
                let value = try await reader.load(container: context.container, accountID: requestedScope.accountID, showAllAccounts: requestedScope.showAll)
                #endif
                try Task.checkCancellation()
                var transaction = SwiftUI.Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    snapshot = value
                    loadedScope = requestedScope
                    loadFailed = false
                    lastSuccessfulLoad = Date()
                }
            } catch is CancellationError {
                // A newer refresh or disappearance owns the next result.
            } catch {
                loadFailed = true // Keep the last successful snapshot during a failed refresh.
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: FinanceDataChangeCenter.notificationName).receive(on: RunLoop.main)) { notification in
            guard let change = FinanceDataChange.from(notification),
                  change.affects(container: context.container, contoIDs: loadedScope == scope ? snapshot?.refreshContoIDs : nil) else { return }
            refreshRevision &+= 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange).receive(on: RunLoop.main)) { _ in
            refreshRevision &+= 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .cloudSyncDidComplete).receive(on: RunLoop.main)) { _ in
            refreshRevision &+= 1
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshRevision &+= 1 }
        }
        .task {
            // Time-dependent estimates must also advance without a save or foreground transition.
            do {
                while !Task.isCancelled {
                    try await Task.sleep(for: .seconds(60))
                    if scenePhase == .active { refreshRevision &+= 1 }
                }
            } catch is CancellationError {}
            catch {}
        }
    }

    private func header(snapshot: TodaySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            #if os(macOS)
            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 10) {
                    FormiLogo(size: 36)
                    Text("Formi")
                        .font(.system(size: 34, weight: .semibold, design: .serif))
                        .tracking(-1)
                }
                .accessibilityElement(children: .combine)
                Spacer()
                Menu {
                    Section("Sezioni") {
                        ForEach(AppTab.optionalChoices, id: \.rawValue) { tab in
                            Button(tab.navigationTitle, systemImage: tab.icon) { appState.selectTab(tab) }
                        }
                    }
                    Button("Personalizza tab", systemImage: "rectangle.bottomthird.inset.filled") {
                        appState.showingTabCustomization = true
                    }
                    Button("Impostazioni", systemImage: "gearshape") { appState.selectTab(.settings) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Sezioni e impostazioni")
                .accessibilityIdentifier("today-sections")
            }
            #endif
            Label(snapshot.accountName, systemImage: "books.vertical")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ForgiaPalette.mutedText)
            Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.caption.weight(.medium))
                .textCase(.uppercase)
                .tracking(0.7)
                .foregroundStyle(ForgiaPalette.mutedText)
        }
        .foregroundStyle(.primary)
    }

}

private struct TodaySectionCards: View {
    @Environment(AppStateManager.self) private var appState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var sections: [AppTab] {
        AppTab.optionalChoices.filter { !appState.compactTabs.contains($0) }
    }

    var body: some View {
        if !sections.isEmpty {
            LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize
                      ? [GridItem(.flexible())]
                      : [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(sections, id: \.rawValue) { tab in
                    Button {
                        appState.selectTab(tab)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(ForgiaPalette.accent)
                                .frame(width: 32, height: 32)
                                .background(ForgiaPalette.sageSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            Text(tab.navigationTitle)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                        .compactCard()
                        .contentShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("today-section-\(tab.rawValue)")
                }
            }
        }
    }
}

private struct TodayRefreshFailureBanner: View {
    let lastSuccessfulLoad: Date?
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Riepilogo non aggiornato", systemImage: "exclamationmark.triangle")
                .font(.subheadline.weight(.semibold))
            Text("L'ultimo aggiornamento non è riuscito. I dati mostrati sono quelli caricati in precedenza.")
                .font(.caption)
            if let lastSuccessfulLoad {
                Text("Ultimo caricamento riuscito: \(lastSuccessfulLoad, format: .dateTime.hour().minute())")
                    .font(.caption)
                    .foregroundStyle(ForgiaPalette.mutedText)
            }
            Button("Riprova", action: retry)
                .buttonStyle(.bordered)
                .accessibilityIdentifier("today-refresh-retry")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .foregroundStyle(.primary)
        .background(ForgiaPalette.apricotSurface)
        .accessibilityIdentifier("today-refresh-failed")
    }
}

private struct TodayMarginCard: View {
    let snapshot: TodaySnapshot
    let onVerify: () -> Void
    let onImport: () -> Void
    let onAddIncome: () -> Void

    var body: some View {
        NavigationLink {
            AnalysisDetailScreen(title: "Il tuo margine", periodTitle: snapshot.accountName, tint: ForgiaPalette.margin) {
                TodayMarginDetailContent(snapshot: snapshot, onVerify: onVerify, onImport: onImport, onAddIncome: onAddIncome)
            }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                AnalysisPreviewHeading(title: "Quanto puoi ancora spendere", icon: "circle.dotted", tint: ForgiaPalette.margin)
                if snapshot.hasMixedCurrencies {
                    Text("Seleziona un solo libro").font(.title3.weight(.semibold))
                    Text("Il margine richiede una sola valuta").font(.subheadline).foregroundStyle(ForgiaPalette.mutedText)
                } else if let margin = snapshot.direction.estimatedMargin {
                    TodayMarginHero(margin: margin,
                                    available: snapshot.direction.liquidBalance - snapshot.direction.creditDebt,
                                    currency: snapshot.currency)
                    Divider().overlay(ForgiaPalette.border)
                    HStack(spacing: 8) {
                        if let nextIncome = snapshot.direction.nextIncome {
                            Label {
                                Text("Fino al \(nextIncome.date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "it_IT"))))")
                            } icon: {
                                Image(systemName: "calendar.badge.clock")
                            }
                            .font(.subheadline).foregroundStyle(ForgiaPalette.mutedText)
                        }
                        Spacer(minLength: 8)
                        Text("Simula una spesa")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ForgiaPalette.margin)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(ForgiaPalette.margin.opacity(0.12), in: Capsule())
                    }
                } else {
                    Text("Stima da completare").font(.title3.weight(.semibold))
                    Label {
                        Text(snapshot.direction.availability.statusMessage)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "list.bullet.clipboard")
                    }
                    .font(.subheadline).foregroundStyle(ForgiaPalette.mutedText)
                }
            }.unifiedCard(tint: ForgiaPalette.margin).foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .financeCardEntrance()
        .accessibilityIdentifier("today-margin-preview")
    }
}

private struct TodayMarginDetailContent: View {
    let snapshot: TodaySnapshot
    let onVerify: () -> Void
    let onImport: () -> Void
    let onAddIncome: () -> Void
    @State private var showsCalculation = false
    @State private var showsMarginInfo = false
    @State private var showsPurchaseCheck = false

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Button { showsMarginInfo = true } label: {
                HStack(spacing: 7) {
                    Text("QUANTO PUOI ANCORA SPENDERE")
                        .font(.caption2.weight(.semibold))
                        .tracking(1.1)
                    Image(systemName: "info.circle").font(.caption)
                    Spacer()
                }
                .foregroundStyle(ForgiaPalette.mutedText)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Come è calcolato quanto puoi ancora spendere")
            .accessibilityIdentifier("today-margin-info")

            if snapshot.hasMixedCurrencies {
                Label("Seleziona un solo libro o una sola valuta per stimare il margine.", systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
            } else if let margin = snapshot.direction.estimatedMargin {
                TodayMarginHero(margin: margin, available: snapshot.direction.liquidBalance - snapshot.direction.creditDebt,
                                currency: snapshot.currency)
                if let nextIncome = snapshot.direction.nextIncome {
                    Text("Fino alla prossima entrata · \(nextIncome.date.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "it_IT"))))")
                        .font(.subheadline)
                        .foregroundStyle(ForgiaPalette.mutedText)
                }
                Text(margin >= 0
                     ? "Margine extra stimato, dopo impegni e spese abituali."
                     : "Le uscite previste superano la disponibilità: rivedi le spese prima della prossima entrata.")
                    .font(.subheadline)
                    .foregroundStyle(margin >= 0 ? ForgiaPalette.mutedText : .red)
                MarginScenarioSection(margin: margin,
                                      available: snapshot.direction.liquidBalance - snapshot.direction.creditDebt,
                                      currency: snapshot.currency)
                MarginEstimateBasis(latestMovement: snapshot.direction.latestMovement)
                Button("Posso fare una spesa?") { showsPurchaseCheck = true }
                    .buttonStyle(.glassProminent)
                    .tint(ForgiaPalette.accent)
                DisclosureGroup("Come è calcolato", isExpanded: $showsCalculation) {
                    VStack(spacing: 9) {
                        TodayAmountRow(label: "Saldo maturato", amount: snapshot.direction.liquidBalance, currency: snapshot.currency)
                        TodayAmountRow(label: "Debito sulle carte", amount: -snapshot.direction.creditDebt, currency: snapshot.currency)
                        TodayAmountRow(label: "Uscite previste", amount: -snapshot.direction.committedOutgoings, currency: snapshot.currency)
                        TodayAmountRow(label: "Spesa abituale stimata", amount: -snapshot.direction.typicalVariableOutgoings, currency: snapshot.currency)
                        Text("Il saldo esclude i movimenti futuri. Le uscite previste includono le spese programmate e le ricorrenze fino alla prossima entrata. Conferma i saldi dei conti prima di decidere una spesa.")
                            .font(.caption)
                            .foregroundStyle(ForgiaPalette.mutedText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.top, 8)
                }
                .font(.subheadline.weight(.medium))
                .tint(ForgiaPalette.accent)
            } else {
                Text("Stima da completare")
                    .font(.system(.title, design: .serif, weight: .semibold))
                Text(statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(ForgiaPalette.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
                if snapshot.direction.availability == .unverifiedBalances {
                    primaryAction("Verifica i saldi", action: onVerify)
                } else if snapshot.direction.availability == .staleData || snapshot.direction.availability == .noMovements {
                    primaryAction("Aggiorna i movimenti", action: onImport)
                } else if snapshot.direction.availability == .noPlannedIncome {
                    primaryAction("Registra la prossima entrata", action: onAddIncome)
                }
                if let latest = snapshot.direction.latestMovement {
                    Text("Ultimo movimento: \(latest.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "it_IT"))))")
                        .font(.caption)
                        .foregroundStyle(ForgiaPalette.mutedText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .unifiedCard(tint: ForgiaPalette.margin)
        .accessibilityElement(children: .contain)
        .sheet(isPresented: $showsMarginInfo) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Un margine, non una promessa")
                            .font(.system(.title2, design: .serif, weight: .semibold))
                        Text("Partiamo dal saldo maturato, sottraiamo il debito sulle carte, le uscite previste e le spese abituali stimate fino alla prossima entrata.")
                        if !snapshot.hasMixedCurrencies {
                            TodayAmountRow(label: "Saldo maturato", amount: snapshot.direction.liquidBalance, currency: snapshot.currency)
                            TodayAmountRow(label: "Debito sulle carte", amount: -snapshot.direction.creditDebt, currency: snapshot.currency)
                            TodayAmountRow(label: "Uscite previste", amount: -snapshot.direction.committedOutgoings, currency: snapshot.currency)
                            TodayAmountRow(label: "Spesa abituale stimata", amount: -snapshot.direction.typicalVariableOutgoings, currency: snapshot.currency)
                        }
                        Text(snapshot.hasMixedCurrencies ? "Seleziona un libro con una sola valuta per ottenere una stima." : snapshot.direction.estimatedMargin == nil ? statusMessage : "La stima dipende dai movimenti registrati e dai saldi verificati. Le entrate future non sono denaro già disponibile.")
                            .font(.callout).foregroundStyle(.secondary)
                    }.padding(24)
                }
                .navigationTitle("Il tuo margine")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fine") { showsMarginInfo = false } } }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showsPurchaseCheck) {
            PurchaseCheckView(margin: snapshot.direction.estimatedMargin, currency: snapshot.currency)
        }
    }

    private var statusMessage: String { snapshot.direction.availability.statusMessage }

    private func primaryAction(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ForgiaPalette.onAccent)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(ForgiaPalette.accent, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct TodayRecentActivityCard: View {
    let snapshot: TodaySnapshot
    @Environment(AppStateManager.self) private var appState

    private var direction: SpendingDirection { snapshot.direction }
    private var categories: [CategoryOutflow] { Array(direction.chartOutflows.prefix(4)) }
    /// Shades of the card's own hue, so the breakdown stays within one colour family.
    private var palette: [Color] {
        [1, 0.68, 0.45, 0.28].map { ForgiaPalette.spending.opacity($0) }
    }
    /// Change versus the previous 30 days, only when there is a meaningful baseline.
    private var change: Double? {
        guard direction.previous30DaysExpenses > 0 else { return nil }
        return NSDecimalNumber(decimal: (direction.recentExpenses - direction.previous30DaysExpenses) / direction.previous30DaysExpenses).doubleValue
    }

    var body: some View {
        NavigationLink {
            SpendingOverviewView(transactions: snapshot.entries, currency: snapshot.currency,
                                 scopeContoIDs: snapshot.contoIDs, initialBookID: appState.showAllAccounts ? nil : appState.selectedAccount?.id)
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                AnalysisPreviewHeading(title: "Dove spendi", icon: "chart.bar.xaxis", tint: ForgiaPalette.spending,
                                       accessory: "30 giorni")
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(direction.recentExpenses, format: .currency(code: snapshot.currency))
                        .font(.system(size: 31, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .financeNumericMotion(direction.recentExpenses)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text("di uscite")
                        .font(.subheadline)
                        .foregroundStyle(ForgiaPalette.mutedText)
                    Spacer(minLength: 4)
                    if let change, abs(change) >= 0.01 {
                        changeBadge(change)
                    }
                }
                if categories.isEmpty {
                    Text("Importa o registra movimenti per scoprire dove spendi.")
                        .font(.subheadline)
                        .foregroundStyle(ForgiaPalette.mutedText)
                } else {
                    categoryBar
                    VStack(spacing: 8) {
                        ForEach(Array(categories.prefix(3).enumerated()), id: \.offset) { index, category in
                            HStack(spacing: 8) {
                                Circle().fill(color(at: index)).frame(width: 8, height: 8)
                                Text(category.name).font(.subheadline).lineLimit(1)
                                Spacer(minLength: 6)
                                Text(category.amount, format: .currency(code: snapshot.currency))
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                            }
                        }
                    }
                }
                if direction.availability == .staleData,
                   let latest = direction.latestMovement {
                    Label("Dati al \(latest.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "it_IT"))))", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(ForgiaPalette.mutedText)
                }
            }
            .foregroundStyle(.primary)
            .unifiedCard(tint: ForgiaPalette.spending)
        }
        .buttonStyle(.plain)
        .financeCardEntrance()
        .accessibilityLabel("Dove spendi, ultimi 30 giorni")
    }

    private func color(at index: Int) -> Color {
        index < palette.count ? palette[index] : ForgiaPalette.mutedText
    }

    /// Proportional strip of the leading categories; the remainder stays neutral.
    private var categoryBar: some View {
        let total = direction.recentExpenses > 0 ? direction.recentExpenses
            : categories.reduce(Decimal(0)) { $0 + $1.amount }
        return GeometryReader { proxy in
            HStack(spacing: 3) {
                ForEach(Array(categories.enumerated()), id: \.offset) { index, category in
                    let share = total > 0 ? NSDecimalNumber(decimal: category.amount / total).doubleValue : 0
                    Capsule()
                        .fill(color(at: index))
                        .frame(width: max(4, (proxy.size.width - 3 * CGFloat(categories.count)) * share))
                }
                Capsule().fill(ForgiaPalette.border)
            }
        }
        .frame(height: 8)
        .financeChartReveal()
        .accessibilityHidden(true)
    }

    private func changeBadge(_ change: Double) -> some View {
        let up = change > 0
        return Label {
            Text(abs(change), format: .percent.precision(.fractionLength(0)))
        } icon: {
            Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
        }
        .font(.caption.weight(.semibold))
        .labelStyle(.titleAndIcon)
        .foregroundStyle(up ? ForgiaPalette.deficit : ForgiaPalette.margin)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background((up ? ForgiaPalette.deficit : ForgiaPalette.margin).opacity(0.12), in: Capsule())
        .fixedSize()
        .accessibilityLabel(up ? "In aumento rispetto ai 30 giorni precedenti" : "In calo rispetto ai 30 giorni precedenti")
    }
}

private struct TodayAmountRow: View {
    let label: String
    let amount: Decimal
    let currency: String

    var body: some View {
        HStack {
            Text(label).foregroundStyle(ForgiaPalette.mutedText)
            Spacer()
            Text(amount, format: .currency(code: currency)).monospacedDigit()
        }
        .font(.subheadline)
    }
}

private struct TodayShiftsCard: View {
    let shifts: [SpendingShift]
    let currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AnalysisPreviewHeading(title: "Da controllare", icon: "exclamationmark.bubble", tint: ForgiaPalette.deficit,
                                   showsChevron: false)
            Text("Categorie sopra il ritmo dei tre mesi precedenti")
                .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
            VStack(spacing: 0) {
                ForEach(Array(shifts.enumerated()), id: \.offset) { index, shift in
                    if index > 0 { Divider().overlay(ForgiaPalette.border) }
                    NavigationLink {
                        TransactionListView(initialCategoryID: shift.categoryID, isPushed: true)
                    } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(shift.categoryName).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Text("Spesi \(shift.spent.formatted(.currency(code: currency))) · attesi \(shift.expectedByToday.formatted(.currency(code: currency)))")
                                    .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                                    .lineLimit(1).minimumScaleFactor(0.85)
                            }
                            Spacer(minLength: 6)
                            Text("+\(shift.excess.formatted(.currency(code: currency)))")
                                .font(.caption.weight(.bold)).monospacedDigit()
                                .foregroundStyle(ForgiaPalette.deficit)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(ForgiaPalette.deficit.opacity(0.12), in: Capsule())
                                .fixedSize()
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                                .foregroundStyle(ForgiaPalette.mutedText).accessibilityHidden(true)
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(shift.categoryName): \(shift.excess.formatted(.currency(code: currency))) oltre il ritmo abituale")
                }
            }
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .unifiedCard(tint: ForgiaPalette.deficit)
        .financeCardEntrance()
    }
}

private struct TodayActivityLayout: View {
    let snapshot: TodaySnapshot
    var body: some View {
        #if os(macOS)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), alignment: .top)], alignment: .leading, spacing: 24) {
            cards
        }
        #else
        cards
        #endif
    }
    @ViewBuilder private var cards: some View {
        TodayRecentActivityCard(snapshot: snapshot)
        if !snapshot.direction.shifts.isEmpty {
            TodayShiftsCard(shifts: snapshot.direction.shifts, currency: snapshot.currency)
        }
    }
}

private extension DirectionAvailability {
    var statusMessage: String {
        switch self {
        case .noMovements: "Aggiungi o importa i movimenti per iniziare."
        case .staleData: "Aggiorna i movimenti: i dati sono troppo vecchi per stimare quanto resta."
        case .shortHistory: "Servono almeno 45 giorni di movimenti per stimare la spesa abituale."
        case .sparseSpending: "Servono più spese recenti, distribuite su almeno due mesi, per stimare un margine attendibile."
        case .unverifiedBalances: "Verifica il saldo attuale di ogni conto e carta prima di usare la stima."
        case .noPlannedIncome: "Registra un'entrata ricorrente prevista entro 45 giorni per calcolare il margine fino a quella data."
        case .ready: ""
        }
    }
}

#if DEBUG
/// Exercises the real margin card without inserting or changing ledger records.
struct TodayMarginVisualFixture: View {
    private var snapshot: TodaySnapshot {
        let now = Date()
        let entries = (0..<30).map { index in
            DirectionTransaction(date: Calendar.current.date(byAdding: .day, value: -(index * 3 + 1), to: now)!,
                amount: 45, type: .expense, categoryID: nil, categoryName: "Spese quotidiane", isRecurring: false)
        }
        let planned = [
            PlannedCashMovement(date: Calendar.current.date(byAdding: .day, value: 14, to: now)!, amount: 2200, type: .income, title: "Stipendio"),
            PlannedCashMovement(date: Calendar.current.date(byAdding: .day, value: 5, to: now)!, amount: 480, type: .expense, title: "Affitto")
        ]
        let direction = SpendingDirectionCalculator.calculate(transactions: entries, planned: planned,
            liquidBalance: 3000, creditDebt: 120, balancesVerified: true, now: now)
        return TodaySnapshot(entries: entries, contoIDs: [], accountName: "Esempio", currency: "EUR",
            hasMixedCurrencies: false, direction: direction, planned: planned.filter { $0.type == .expense })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Anteprima · dati illustrativi").font(.caption).foregroundStyle(.secondary)
                    TodayMarginCard(snapshot: snapshot, onVerify: {}, onImport: {}, onAddIncome: {})
                }.padding(22)
            }
            .themedBackground(tint: ForgiaPalette.margin)
            .navigationTitle("Il tuo margine")
            .toolbarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("UITEST_VISUAL_DARK") ? .dark : nil)
        .dynamicTypeSize(ProcessInfo.processInfo.arguments.contains("UITEST_VISUAL_LARGE_TEXT") ? .accessibility3 : .large)
    }
}
#endif
