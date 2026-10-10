//
//  MainTabView.swift
//  Personal Finance
//
//  Tab principale con navigazione semplificata e supporto iOS 26 Liquid Glass
//

import SwiftUI
import SwiftData
import FinanceCore

struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var bookSelectionNamespace
    @Environment(AppStateManager.self) private var appState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var shortcutInbox = FinanceShortcutInbox.shared
    @State private var showingVoice = false
    @Environment(AppLock.self) private var appLock
    @Query private var widgetAccounts: [Account]
    #if os(macOS)
    @State private var showingMacImport = false
    @State private var showingMacExport = false
    #endif

    private var usesSidebar: Bool {
        #if os(macOS)
        true
        #else
        horizontalSizeClass == .regular
        #endif
    }

    private var themeColor: Color {
        appState.themeManager.currentTheme.color
    }

    var body: some View {
        Group {
            #if os(macOS)
            macLayout
            #else
            if usesSidebar {
                iPadLayout
            } else {
                iPhoneLayout
            }
            #endif
        }
        #if os(macOS)
        .modifier(FinanceMacCommandScope())
        #endif
        .onChange(of: appLock.shouldConceal) { _, concealed in if !concealed { deliverShortcut() } }
        .onChange(of: shortcutInbox.pending, initial: true) { _, _ in deliverShortcut() }
        .onChange(of: appState.showingQuickTransaction) { _, showing in if !showing { deliverShortcut() } }
        .onChange(of: appState.showingTransferSheet) { _, showing in if !showing { deliverShortcut() } }
        .onChange(of: appState.showingAccountSelection) { _, showing in if !showing { deliverShortcut() } }
        .onChange(of: appState.showingAccountCreation) { _, showing in if !showing { deliverShortcut() } }
        .alert("Richiesta di Formi", isPresented: Binding(get: { shortcutInbox.errorMessage != nil }, set: { if !$0 { shortcutInbox.errorMessage = nil } })) {
            Button("OK") { shortcutInbox.errorMessage = nil }
        } message: { Text(shortcutInbox.errorMessage ?? "") }
        .environment(\.cardTint, themeColor)
        .environment(\.tintedBackgrounds, appState.tintedBackgrounds)
        .financePresentation(isPresented: $showingVoice, title: "Aggiungi con la voce", width: 600, height: 720) {
            VoiceTransactionView()
        }
        .financePresentation(isPresented: Binding(
            get: { appState.showingQuickTransaction },
            set: { _ in appState.dismissQuickTransaction() }
        ), title: "Nuovo movimento") {
            QuickTransactionModal()
        }
        .financePresentation(isPresented: Binding(
            get: { appState.showingTransferSheet },
            set: { _ in appState.dismissTransferSheet() }
        ), title: "Nuovo trasferimento") {
            CreateTransactionView(conto: nil, transactionType: .transfer)
        }
        .sheet(isPresented: Binding(
            get: { appState.showingAccountSelection },
            set: { _ in appState.dismissAccountSelection() }
        )) {
            bookSelectionSheet
        }
    }

    @ViewBuilder
    private var bookSelectionSheet: some View {
        #if os(iOS)
        if appState.selectedTab == .dashboard && !reduceMotion {
            AccountSelectionModal()
                .navigationTransition(.zoom(sourceID: "home-book-picker", in: bookSelectionNamespace))
        } else {
            AccountSelectionModal()
        }
        #else
        AccountSelectionModal()
        #endif
    }

    private func deliverShortcut() {
        #if os(iOS)
        WatchPhoneBridge.shared.flushDraft()
        #endif
        shortcutInbox.deliver(to: appState, canAccessContent: !appLock.shouldConceal, accounts: widgetAccounts)
    }

    // MARK: - iPhone Layout

    private var iPhoneLayout: some View {
        Group {
            if #available(iOS 26, macOS 26, *) {
                iOS26TabView
            } else {
                legacyTabView
            }
        }
        // One button for the whole tab bar, floating just above it.
        .overlay(alignment: .bottomTrailing) { transactionButton(bottomPadding: 70) }
        .animation(.snappy(duration: 0.2), value: appState.showsTransactionButton)
    }

    @ViewBuilder
    private func transactionButton(bottomPadding: CGFloat) -> some View {
        if appState.showsTransactionButton {
            TransactionAddButton()
                .padding(.trailing, 20)
                .padding(.bottom, bottomPadding)
                .transition(.scale(scale: 0.85, anchor: .bottomTrailing).combined(with: .opacity))
        }
    }

    /// iPhone has no search tab: a search selected on iPad falls back to Movimenti when the width shrinks.
    private var compactTabSelection: Binding<AppTab> {
        Binding(
            get: { appState.selectedTab == .search ? .transactions : appState.selectedTab },
            set: { appState.selectTab($0) }
        )
    }

    // MARK: - iOS 26+ TabView

    @available(iOS 26, macOS 26, *)
    private var iOS26TabView: some View {
        TabView(selection: compactTabSelection) {
            Tab(value: AppTab.dashboard) {
                TodayView(bookSelectionNamespace: bookSelectionNamespace)
            } label: {
                Label("Oggi", systemImage: "house")
            }

            Tab(value: AppTab.analysis) {
                TodayView(screen: .analysis)
            } label: {
                Label("Analisi", systemImage: "chart.pie")
            }

            Tab(value: AppTab.transactions) {
                TransactionListView()
            } label: {
                Label("Movimenti", systemImage: "list.bullet.rectangle")
            }

            Tab(value: AppTab.planning) {
                FinancePlanningView()
            } label: {
                Label("Pianifica", systemImage: "calendar")
            }

            Tab(value: AppTab.settings) {
                SettingsView()
            } label: {
                Label("Altro", systemImage: "ellipsis")
            }
        }
    }

    // MARK: - Legacy TabView (iOS 18-25)

    private var legacyTabView: some View {
        TabView(selection: compactTabSelection) {
            TodayView(bookSelectionNamespace: bookSelectionNamespace)
                .tabItem {
                    Label("Oggi", systemImage: "house")
                }
                .tag(AppTab.dashboard)

            TodayView(screen: .analysis)
                .tabItem {
                    Label("Analisi", systemImage: "chart.pie")
                }
                .tag(AppTab.analysis)

            TransactionListView()
                .tabItem {
                    Label("Movimenti", systemImage: "list.bullet.rectangle")
                }
                .tag(AppTab.transactions)

            FinancePlanningView()
                .tabItem { Label("Pianifica", systemImage: "calendar") }
                .tag(AppTab.planning)

            SettingsView()
                .tabItem {
                    Label("Altro", systemImage: "ellipsis")
                }
                .tag(AppTab.settings)
        }
    }

    #if os(macOS)
    private var macLayout: some View {
        NavigationSplitView {
            List(selection: Binding(
                get: { appState.selectedTab },
                set: { if let tab = $0 { appState.selectTab(tab) } }
            )) {
                Section("Panoramica") {
                    Label("Oggi", systemImage: "house").tag(AppTab.dashboard)
                    Label("Analisi", systemImage: "chart.pie").tag(AppTab.analysis)
                }
                Section("Gestisci") {
                    Label("Movimenti", systemImage: "list.bullet.rectangle").tag(AppTab.transactions)
                    Label("Cerca", systemImage: "magnifyingglass").tag(AppTab.search)
                    Label("Pianifica", systemImage: "calendar").tag(AppTab.planning)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Formi")
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 12) {
                    Menu {
                        Button("Tutti i libri") { appState.selectAllAccounts() }
                        Divider()
                        ForEach(widgetAccounts.filter { $0.isActive == true }, id: \.id) { account in
                            Button(account.name ?? "Libro") { appState.selectAccount(account) }
                        }
                        Divider()
                        Button("Gestisci libri…") { appState.showingSettingsWindow = true }
                    } label: {
                        Label(appState.showAllAccounts ? "Tutti i libri" : appState.selectedAccount?.name ?? "Scegli libro", systemImage: "books.vertical")
                            .lineLimit(1)
                    }
                    Button("Impostazioni…", systemImage: "gearshape") { appState.showingSettingsWindow = true }
                }
                .buttonStyle(.borderless)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.bar)
            }
        } detail: {
            detailContent
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button("Nuova spesa", systemImage: "plus") { appState.presentQuickTransaction() }
                            .buttonStyle(.glassProminent)
                            .help("Nuova spesa (⌘N)")
                            .disabled(appState.showingQuickTransaction)
                        Menu {
                            Button("Aggiungi con la voce", systemImage: "mic.fill") { showingVoice = true }
                            Button("Nuova entrata", systemImage: "arrow.down.left") { appState.presentQuickTransaction(type: .income) }
                            Button("Nuovo trasferimento", systemImage: "arrow.left.arrow.right") { appState.presentQuickTransaction(type: .transfer) }
                                .disabled(appState.activeConti(for: appState.selectedAccount).count < 2)
                            Divider()
                            Button("Importa CSV…") { showingMacImport = true }
                            Button("Esporta CSV…") { showingMacExport = true }
                        } label: { Label("Altre azioni", systemImage: "ellipsis.circle") }
                    }
                }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 780, minHeight: 520)
        .financePresentation(isPresented: Binding(
            get: { appState.showingSettingsWindow },
            set: { appState.showingSettingsWindow = $0 }
        ), title: "Impostazioni", width: 960, height: 740, pinsBook: false) { SettingsView() }
        .financePresentation(isPresented: $showingMacImport, title: "Importa CSV", width: 800) { CSVImportView() }
        .financePresentation(isPresented: $showingMacExport, title: "Esporta CSV", width: 800) { CSVExportView() }
    }
    #endif

    // MARK: - iPad Layout

    private var iPadLayout: some View {
        NavigationSplitView {
            List(selection: Binding(
                get: { appState.selectedTab },
                set: { if let tab = $0 { appState.selectTab(tab) } }
            )) {
                Section("Menu") {
                    Label("Oggi", systemImage: "house")
                        .tag(AppTab.dashboard)

                    Label("Analisi", systemImage: "chart.pie")
                        .tag(AppTab.analysis)

                    Label("Movimenti", systemImage: "list.bullet.rectangle")
                        .tag(AppTab.transactions)

                    Label("Cerca", systemImage: "magnifyingglass")
                        .tag(AppTab.search)

                    Label("Pianifica", systemImage: "calendar")
                        .tag(AppTab.planning)

                    Label("Impostazioni", systemImage: "gearshape")
                        .tag(AppTab.settings)
                }
            }
            .navigationTitle("Formi")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        appState.presentQuickTransaction()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                    .accessibilityLabel("Nuova spesa")
                    #if !os(macOS)
                    .keyboardShortcut("n", modifiers: .command)
                    #endif
                }
            }
        } detail: {
            detailContent
                .overlay(alignment: .bottomTrailing) { transactionButton(bottomPadding: 16) }
        }
        .animation(.snappy(duration: 0.2), value: appState.showsTransactionButton)
    }

    @ViewBuilder
    private var detailContent: some View {
            switch appState.selectedTab {
            case .dashboard:
                TodayView(bookSelectionNamespace: bookSelectionNamespace)
            case .analysis:
                TodayView(screen: .analysis)
            case .transactions:
                TransactionListView()
            case .search:
                NavigationStack {
                    TransactionSearchView()
                }
            case .planning:
                FinancePlanningView()
            case .settings:
                SettingsView()
            case .addTransaction:
                TodayView(bookSelectionNamespace: bookSelectionNamespace)
            }
    }
}

// MARK: - Quick Transaction Modal

struct QuickTransactionModal: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStateManager.self) private var appState

    @State private var selectedConto: Conto?
    @State private var destinationConto: Conto?
    @State private var destinationAmount = ""
    @State private var showingDestinationPicker = false
    @State private var selectedCategory: FinanceCategory?
    @State private var amount: String = ""
    @State private var foreignAmount: ForeignAmountDraft?
    @State private var showingConversion = false
    @State private var place = PlaceDraft()
    @State private var loadingLocation = false
    @State private var attachmentDrafts: [AttachmentDraft] = []
    @State private var loadingAttachment = false
    @State private var description: String = ""
    @State private var transactionType: TransactionType = .expense
    @State private var selectedDate = Date()
    @State private var isRecurring = false
    @State private var recurrenceFrequency: RecurrenceFrequency = .monthly
    @State private var hasRecurrenceEndDate = false
    @State private var recurrenceEndDate = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    @State private var saveError: String?
    @State private var showingCalculator = false
    @State private var showingAccountPicker = false
    @State private var showingCategoryPicker = false
    @FocusState private var amountFocused: Bool
    @State private var riskLevel: SpendingRisk.Level?
    @State private var shakeCount: CGFloat = 0

    private var availableConti: [Conto] {
        appState.activeConti(for: appState.selectedAccount)
    }

    private var availableCategories: [FinanceCategory] {
        appState.selectedAccount?.categories?.filter { $0.isActive == true } ?? []
    }

    private var parsedAmount: Decimal? {
        BalanceInput.parse(amount, currency: selectedConto?.account?.currency ?? "EUR")
    }

    private var movementTitle: String {
        switch transactionType {
        case .expense: "Nuova spesa"
        case .income: "Nuova entrata"
        case .transfer: "Nuovo trasferimento"
        }
    }

    private var saveTitle: String {
        switch transactionType {
        case .expense: "Salva spesa"
        case .income: "Salva entrata"
        case .transfer: "Salva trasferimento"
        }
    }

    private var hasDifferentCurrencies: Bool {
        guard let selectedConto, let destinationConto else { return false }
        return (selectedConto.account?.currency ?? "EUR") != (destinationConto.account?.currency ?? "EUR")
    }

    private var parsedDestinationAmount: Decimal? {
        BalanceInput.parse(destinationAmount, currency: destinationConto?.account?.currency ?? "EUR")
    }

    private var effectiveRecurrenceEndDate: Date? {
        RecurrenceSchedule.inclusiveEnd(anchor: selectedDate, lastDay: recurrenceEndDate)
    }

    private var isFormValid: Bool {
        if isRecurring && hasRecurrenceEndDate && effectiveRecurrenceEndDate == nil { return false }
        guard let amountValue = parsedAmount else {
            return false
        }
        guard let selectedConto, availableConti.contains(where: { $0.id == selectedConto.id }),
              amountValue > 0, !loadingAttachment, !loadingLocation else { return false }
        if transactionType == .transfer {
            guard let destinationConto, destinationConto.id != selectedConto.id,
                  availableConti.contains(where: { $0.id == destinationConto.id }) else { return false }
            return !hasDifferentCurrencies || (parsedDestinationAmount ?? 0) > 0
        }
        return selectedCategory != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if transactionType != .transfer {
                        VoiceTransactionEntryButton(onComplete: { dismiss() }, onOpen: { amountFocused = false })
                    }
                    typeSelector
                    amountCard
                    if transactionType == .expense, let proposedAmount = parsedAmount {
                        SpendingRiskBanner(amount: proposedAmount, categoryID: selectedCategory?.id,
                                           accountID: selectedConto?.account?.id, conto: selectedConto,
                                           date: selectedDate, currency: selectedConto?.account?.currency ?? "EUR") { level in
                            // Shake only when things get worse, not on every keystroke.
                            if let level, riskLevel.map({ level > $0 }) ?? true {
                                withAnimation(.linear(duration: 0.45)) { shakeCount += 1 }
                            }
                            riskLevel = level
                        }
                    }
                    if transactionType != .transfer {
                        Button("Importo in valuta estera", systemImage: "arrow.left.arrow.right") {
                            amountFocused = false
                            showingConversion = true
                        }
                        if let foreignAmount {
                            Text("\(foreignAmount.originalAmount.formatted(.currency(code: foreignAmount.originalCurrency))) · cambio \(foreignAmount.rate.formatted())")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } else if hasDifferentCurrencies {
                        FormCard(title: "Importo ricevuto") {
                            HStack {
                                Text(destinationConto?.account?.currency ?? "EUR")
                                TextField("0,00", text: $destinationAmount)
                                    #if os(iOS)
                                    .keyboardType(.decimalPad)
                                    #endif
                                    .accessibilityLabel("Importo ricevuto")
                            }
                        }
                    }
                    if transactionType == .transfer, availableConti.count < 2 {
                        Text("Per un trasferimento servono almeno due conti attivi nello stesso libro. Aggiungi un altro conto dalle Impostazioni.")
                            .font(.subheadline)
                            .foregroundStyle(ForgiaPalette.mutedText)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        sectionTitle("Dettagli")
                        detailsCard
                    }

                    if transactionType == .expense,
                       let proposedAmount = parsedAmount,
                       proposedAmount > 0 {
                        if let category = selectedCategory, let conto = selectedConto,
                           let account = conto.account {
                            ExpenseBudgetCheckView(
                                amount: proposedAmount, categoryID: category.id,
                                accountID: account.id, date: selectedDate,
                                currency: account.currency ?? "EUR", isRecurring: isRecurring
                            )
                        } else {
                            Label("Scegli conto e categoria per verificare i budget.", systemImage: "info.circle")
                                .font(.subheadline)
                                .foregroundStyle(ForgiaPalette.mutedText)
                        }
                    }


                    VStack(alignment: .leading, spacing: 8) {
                        sectionTitle("Ricorrenza")
                        recurrenceCard
                    }
                    TransactionPlaceEditor(place: $place, isLocating: $loadingLocation, cardStyle: true)
                    DraftAttachmentsView(attachments: $attachmentDrafts, onSelectAmount: {
                        amount = NSDecimalNumber(decimal: $0).stringValue.replacingOccurrences(of: ".", with: ",")
                    }, loading: $loadingAttachment, cardStyle: true)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)
            }
            .background(ForgiaPalette.canvas)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(movementTitle)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                #if os(macOS)
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveTitle, action: saveTransaction)
                        .keyboardShortcut("s", modifiers: .command)
                        .disabled(!isFormValid)
                }
                #endif
            }
            #if !os(macOS)
            .safeAreaBar(edge: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Button(action: saveTransaction) {
                        Text(saveTitle)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(isFormValid ? ForgiaPalette.accent : ForgiaPalette.border,
                                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .foregroundStyle(isFormValid ? ForgiaPalette.onAccent : ForgiaPalette.mutedText)
                    }
                    .disabled(!isFormValid)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                }
            }
            #endif
            .sheet(isPresented: $showingConversion) {
                CurrencyConversionSheet(targetCurrency: selectedConto?.account?.currency ?? "EUR", transactionDate: selectedDate, existing: foreignAmount) { value in
                    foreignAmount = value
                    amount = NSDecimalNumber(decimal: value.converted ?? 0).stringValue.replacingOccurrences(of: ".", with: ",")
                }
            }
            .onChange(of: amount) { _, value in
                if let foreignAmount, BalanceInput.parse(value, currency: selectedConto?.account?.currency ?? "EUR") != foreignAmount.converted { self.foreignAmount = nil }
            }
            .sheet(isPresented: $showingCalculator) {
                AmountCalculatorView(initialAmount: parsedAmount ?? 0,
                                     currency: selectedConto?.account?.currency ?? "EUR") { result in
                    amount = NSDecimalNumber(decimal: result).stringValue.replacingOccurrences(of: ".", with: ",")
                }
            }
            .alert("Impossibile salvare", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) { saveError = nil }
            } message: {
                Text(saveError ?? "Riprova tra poco.")
            }
            .confirmationDialog("Scegli un conto", isPresented: $showingAccountPicker, titleVisibility: .visible) {
                ForEach(availableConti, id: \.id) { conto in
                    Button(conto.name ?? "Conto") { selectedConto = conto }
                }
            }
            .confirmationDialog("Al conto", isPresented: $showingDestinationPicker, titleVisibility: .visible) {
                ForEach(availableConti.filter { $0.id != selectedConto?.id }, id: \.id) { conto in
                    Button(conto.name ?? "Conto") { destinationConto = conto }
                }
            }
            .onChange(of: selectedConto?.id) { _, _ in
                if destinationConto?.id == selectedConto?.id { destinationConto = nil }
            }
            .onChange(of: destinationConto?.id) { _, _ in destinationAmount = "" }
            .sheet(isPresented: $showingCategoryPicker) {
                CategoryPickerSheet(categories: availableCategories, type: transactionType, selection: $selectedCategory)
            }
            .onChange(of: transactionType) { _, type in
                // An income category can't classify an expense, and vice versa.
                if selectedCategory?.fits(type) == false { selectedCategory = nil }
                if type == .transfer {
                    foreignAmount = nil
                    if destinationConto == nil {
                        destinationConto = availableConti.first { $0.id != selectedConto?.id }
                    }
                }
            }
            .onAppear {
                transactionType = appState.quickTransactionType
                if let prefill = appState.quickTransactionPrefill {
                    amount = prefill.amount
                    description = prefill.description
                    appState.quickTransactionPrefill = nil
                }
                if appState.quickTransactionIsPlanned {
                    isRecurring = true
                    selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                }
                if selectedConto == nil, let firstConto = availableConti.first {
                    selectedConto = firstConto
                }
                if transactionType == .transfer, destinationConto == nil {
                    destinationConto = availableConti.first { $0.id != selectedConto?.id }
                }
            }
        }
    }

    private var typeSelector: some View {
        HStack(spacing: 4) {
            typeButton(.expense, title: "Spesa", icon: "arrow.up.right")
            typeButton(.income, title: "Entrata", icon: "arrow.down.left")
            typeButton(.transfer, title: "Trasferimento", icon: "arrow.left.arrow.right")
        }
        .padding(4)
        .background(ForgiaPalette.surface, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
    }

    private func typeButton(_ type: TransactionType, title: String, icon: String) -> some View {
        let selected = transactionType == type
        return Button {
            amountFocused = false
            transactionType = type
        } label: {
            ViewThatFits(in: .horizontal) {
                Label(title, systemImage: icon)
                Text(title)
            }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 45)
                .foregroundStyle(selected ? ForgiaPalette.accent : ForgiaPalette.mutedText)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(type == .expense ? ForgiaPalette.apricotSurface : ForgiaPalette.sageSurface)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("quick-type-\(type.rawValue)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var amountCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(transactionType == .transfer ? "IMPORTO TRASFERITO" : "IMPORTO")
                    .font(.caption2.weight(.semibold)).tracking(1.2)
                    .foregroundStyle(ForgiaPalette.mutedText)
                Spacer()
                Button {
                    amountFocused = false
                    showingCalculator = true
                } label: { Label("Calcolatrice", systemImage: "plus.forwardslash.minus") }
                    .font(.subheadline)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(selectedConto?.account?.currency ?? "EUR")
                    .font(.headline)
                    .foregroundStyle(ForgiaPalette.accent)

                TextField("0,00", text: $amount)
                    .focused($amountFocused)
#if os(iOS)
                    .keyboardType(.decimalPad)
#endif
                    .accessibilityLabel("Importo")

                if !amount.isEmpty {
                    Button {
                        amount = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(ForgiaPalette.mutedText)
                    }
                    .accessibilityLabel("Cancella importo")
                }
            }
            .font(.system(size: 45, weight: .semibold, design: .rounded))
            .minimumScaleFactor(0.7)
            .foregroundStyle(riskLevel == .over && transactionType == .expense ? Color.red : Color.primary)
            .animation(.snappy, value: riskLevel)
            .modifier(ShakeEffect(animatableData: shakeCount))
            #if os(iOS)
            .sensoryFeedback(.warning, trigger: shakeCount)
            #endif
            if !amount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               parsedAmount == nil || (parsedAmount ?? 0) <= 0 {
                Text("Inserisci un importo positivo valido per la valuta del conto, senza separatori delle migliaia.")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("quick-amount-invalid")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 120)
        .background(ForgiaPalette.surface, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
    }

    private var detailsCard: some View {
        VStack(spacing: 0) {
            Button {
                amountFocused = false
                showingAccountPicker = true
            } label: {
                selectionRow(
                    icon: "creditcard",
                    title: transactionType == .transfer ? "Dal conto" : transactionType == .expense ? "Da quale conto" : "Su quale conto",
                    value: selectedConto?.name ?? "Seleziona un conto",
                    tint: ForgiaPalette.sageSurface
                )
            }
            .buttonStyle(.plain)
            .disabled(availableConti.isEmpty)
            .accessibilityLabel(transactionType == .transfer ? "Dal conto" : "Conto")

            rowDivider

            if transactionType == .transfer {
                Button {
                    amountFocused = false
                    showingDestinationPicker = true
                } label: {
                    selectionRow(icon: "arrow.down.left", title: "Al conto",
                                 value: destinationConto?.name ?? "Seleziona un conto",
                                 tint: ForgiaPalette.sageSurface)
                }
                .buttonStyle(.plain)
                .disabled(availableConti.filter { $0.id != selectedConto?.id }.isEmpty)
                .accessibilityLabel("Al conto")
            } else {
                Button {
                    amountFocused = false
                    showingCategoryPicker = true
                } label: {
                    selectionRow(
                        icon: selectedCategory?.icon ?? "tag",
                        title: "Categoria",
                        value: selectedCategory?.displayPath ?? "Seleziona una categoria",
                        tint: transactionType == .expense ? ForgiaPalette.apricotSurface : ForgiaPalette.sageSurface
                    )
                }
                .buttonStyle(.plain)
                .disabled(availableCategories.isEmpty)
                .accessibilityLabel("Categoria")

            }

            rowDivider

            HStack(spacing: 14) {
                rowIcon("text.alignleft", tint: ForgiaPalette.canvas)
                TextField("Aggiungi una nota (opzionale)", text: $description)
                    .font(.body)
                    .accessibilityLabel("Descrizione")
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 62)

            rowDivider

            HStack(spacing: 14) {
                rowIcon("calendar", tint: ForgiaPalette.canvas)
                Text("Data")
                    .font(.body)
                Spacer(minLength: 8)
                DatePicker("Data", selection: $selectedDate, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .tint(ForgiaPalette.accent)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 62)
        }
        .background(ForgiaPalette.surface, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
    }

    private var recurrenceCard: some View {
        FormCard {
            RecurrenceEditorRows(
                isRecurring: $isRecurring,
                frequency: $recurrenceFrequency,
                hasEndDate: $hasRecurrenceEndDate,
                endDate: $recurrenceEndDate,
                startDate: selectedDate
            )
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ForgiaPalette.mutedText)
            .padding(.leading, 4)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(ForgiaPalette.border)
            .frame(height: 1)
            .padding(.leading, 64)
            .padding(.trailing, 16)
    }

    private func rowIcon(_ name: String, tint: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(ForgiaPalette.accent)
            .frame(width: 38, height: 38)
            .background(tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func selectionRow(icon: String, title: String, value: String, tint: Color) -> some View {
        HStack(spacing: 14) {
            rowIcon(icon, tint: tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(ForgiaPalette.mutedText)
                Text(value)
                    .font(.body)
                    .foregroundStyle(value.hasPrefix("Seleziona") ? ForgiaPalette.mutedText : Color.primary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ForgiaPalette.mutedText)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 68)
        .contentShape(Rectangle())
    }

    private func saveTransaction() {
        guard isFormValid, let amountDecimal = parsedAmount,
              let conto = selectedConto else { return }

        let transaction = FinanceTransaction(
            amount: amountDecimal,
            type: transactionType,
            date: selectedDate,
            transactionDescription: description.isEmpty ? nil : description,
            isRecurring: isRecurring,
            recurrenceFrequency: isRecurring ? recurrenceFrequency : nil,
            recurrenceEndDate: isRecurring && hasRecurrenceEndDate ? effectiveRecurrenceEndDate : nil
        )

        transaction.setCategory(transactionType == .transfer ? nil : selectedCategory)

        switch transactionType {
        case .expense:
            transaction.setFromConto(conto)
        case .income:
            transaction.setToConto(conto)
        case .transfer:
            guard let destinationConto else { return }
            transaction.setFromConto(conto)
            transaction.setToConto(destinationConto)
            transaction.destinationAmount = hasDifferentCurrencies ? parsedDestinationAmount : nil
            if description.isEmpty {
                transaction.transactionDescription = "Trasferimento da \(conto.name ?? "Conto") a \(destinationConto.name ?? "Conto")"
            }
        }

        if transactionType != .transfer { foreignAmount?.apply(to: transaction) }
        place.apply(to: transaction)
        transaction.attachments = attachmentDrafts.map { $0.model() }
        modelContext.insert(transaction)

        do {
            try modelContext.save()
            appState.triggerDataRefresh()
            dismiss()
        } catch {
            modelContext.delete(transaction)
            saveError = "Il movimento non è stato salvato. Riprova."
        }
    }
}

// MARK: - Preview

#Preview {
    MainTabView()
        .environment(AppStateManager())
        .environment(RecurrenceReminders())
        .environment(AppLock())
        .environment(DataStorageManager.shared)
        .environment(NavigationRouter())
        .modelContainer(try! FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true))
}
