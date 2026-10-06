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
    @Environment(AppStateManager.self) private var appState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var shortcutInbox = FinanceShortcutInbox.shared
    @Environment(AppLock.self) private var appLock
    @Query private var widgetAccounts: [Account]

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
            if usesSidebar {
                iPadLayout
            } else {
                iPhoneLayout
            }
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
        .alert("Richiesta di Forgia", isPresented: Binding(get: { shortcutInbox.errorMessage != nil }, set: { if !$0 { shortcutInbox.errorMessage = nil } })) {
            Button("OK") { shortcutInbox.errorMessage = nil }
        } message: { Text(shortcutInbox.errorMessage ?? "") }
        .environment(\.cardTint, themeColor)
        .environment(\.tintedBackgrounds, appState.tintedBackgrounds)
        .sheet(isPresented: Binding(
            get: { appState.showingQuickTransaction },
            set: { _ in appState.dismissQuickTransaction() }
        )) {
            QuickTransactionModal()
        }
        .sheet(isPresented: Binding(
            get: { appState.showingTransferSheet },
            set: { _ in appState.dismissTransferSheet() }
        )) {
            CreateTransactionView(conto: nil, transactionType: .transfer)
        }
        .sheet(isPresented: Binding(
            get: { appState.showingAccountSelection },
            set: { _ in appState.dismissAccountSelection() }
        )) {
            AccountSelectionModal()
        }
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
                TodayView()
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
            TodayView()
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
            .navigationTitle("Forgia")
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
            switch appState.selectedTab {
            case .dashboard:
                TodayView()
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
                TodayView()
            }
        }
    }
}

// MARK: - Quick Transaction Modal

struct QuickTransactionModal: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStateManager.self) private var appState

    @State private var selectedConto: Conto?
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
    @State private var saveError: String?
    @State private var showingCalculator = false
    @State private var showingAccountPicker = false
    @State private var showingCategoryPicker = false
    @FocusState private var amountFocused: Bool

    private var availableConti: [Conto] {
        appState.activeConti(for: appState.selectedAccount)
    }

    private var availableCategories: [FinanceCategory] {
        appState.selectedAccount?.categories?.filter { $0.isActive == true } ?? []
    }

    private var parsedAmount: Decimal? {
        BalanceInput.parse(amount, currency: selectedConto?.account?.currency ?? "EUR")
    }

    private var isFormValid: Bool {
        guard let amountValue = parsedAmount else {
            return false
        }
        return selectedConto != nil && selectedCategory != nil && amountValue > 0 && !loadingAttachment && !loadingLocation
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    typeSelector
                    amountCard
                    Button("Importo in valuta estera", systemImage: "arrow.left.arrow.right") {
                        amountFocused = false
                        showingConversion = true
                    }
                    if let foreignAmount {
                        Text("\(foreignAmount.originalAmount.formatted(.currency(code: foreignAmount.originalCurrency))) · cambio \(foreignAmount.rate.formatted())")
                            .font(.caption).foregroundStyle(.secondary)
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
                        sectionTitle("Dettagli")
                        detailsCard
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        sectionTitle("Ricorrenza")
                        recurrenceCard
                    }
                    TransactionPlaceEditor(place: $place, isLocating: $loadingLocation).padding(16).unifiedCard()
                    DraftAttachmentsView(attachments: $attachmentDrafts, onSelectAmount: {
                        amount = NSDecimalNumber(decimal: $0).stringValue.replacingOccurrences(of: ".", with: ",")
                    }, loading: $loadingAttachment)
                        .padding(16).unifiedCard()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)
            }
            .background(ForgiaPalette.canvas)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(transactionType == .expense ? "Nuova spesa" : "Nuova entrata")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    if transactionType == .expense,
                       let proposedAmount = parsedAmount,
                       proposedAmount > 0, let category = selectedCategory,
                       let book = selectedConto?.account {
                        ExpenseBudgetCheckView(amount: proposedAmount, categoryID: category.id,
                                               accountID: book.id, date: selectedDate,
                                               currency: book.currency ?? "EUR", isRecurring: isRecurring, compact: true)
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                    }
                    Button(action: saveTransaction) {
                        Text(transactionType == .expense ? "Salva spesa" : "Salva entrata")
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
                    .background(ForgiaPalette.canvas)
                }
                .background(ForgiaPalette.canvas)
            }
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
            .sheet(isPresented: $showingCategoryPicker) {
                NavigationStack {
                    List(availableCategories, id: \.id) { category in
                        Button {
                            selectedCategory = category
                            showingCategoryPicker = false
                        } label: {
                            Label(category.name ?? "Categoria", systemImage: category.icon ?? "tag")
                        }
                    }
                    .navigationTitle("Scegli una categoria")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Annulla") { showingCategoryPicker = false }
                        }
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
            }
        }
    }

    private var typeSelector: some View {
        HStack(spacing: 4) {
            typeButton(.expense, title: "Spesa", icon: "arrow.up.right")
            typeButton(.income, title: "Entrata", icon: "arrow.down.left")
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
            Label(title, systemImage: icon)
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
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var amountCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("IMPORTO")
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
                    title: transactionType == .expense ? "Da quale conto" : "Su quale conto",
                    value: selectedConto?.name ?? "Seleziona un conto",
                    tint: ForgiaPalette.sageSurface
                )
            }
            .buttonStyle(.plain)
            .disabled(availableConti.isEmpty)
            .accessibilityLabel("Conto")

            rowDivider

            Button {
                amountFocused = false
                showingCategoryPicker = true
            } label: {
                selectionRow(
                    icon: selectedCategory?.icon ?? "tag",
                    title: "Categoria",
                    value: selectedCategory?.name ?? "Seleziona una categoria",
                    tint: transactionType == .expense ? ForgiaPalette.apricotSurface : ForgiaPalette.sageSurface
                )
            }
            .buttonStyle(.plain)
            .disabled(availableCategories.isEmpty)
            .accessibilityLabel("Categoria")

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
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                rowIcon("arrow.triangle.2.circlepath", tint: ForgiaPalette.sageSurface)
                Toggle("Transazione ricorrente", isOn: $isRecurring)
                    .tint(ForgiaPalette.accent)
                    .font(.body)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 62)

            if isRecurring {
                rowDivider
                HStack(spacing: 14) {
                    rowIcon("calendar.badge.clock", tint: ForgiaPalette.canvas)
                    Picker("Frequenza", selection: $recurrenceFrequency) {
                        ForEach(RecurrenceFrequency.allCases, id: \.self) { frequency in
                            Text(frequency.displayName).tag(frequency)
                        }
                    }
                    .tint(ForgiaPalette.accent)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 62)
            }
        }
        .background(ForgiaPalette.surface, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
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
              let conto = selectedConto,
              let category = selectedCategory else { return }

        let transaction = FinanceTransaction(
            amount: amountDecimal,
            type: transactionType,
            date: selectedDate,
            transactionDescription: description.isEmpty ? nil : description,
            isRecurring: isRecurring,
            recurrenceFrequency: isRecurring ? recurrenceFrequency : nil
        )

        transaction.setCategory(category)

        switch transactionType {
        case .expense:
            transaction.setFromConto(conto)
        case .income:
            transaction.setToConto(conto)
        case .transfer:
            break
        }

        foreignAmount?.apply(to: transaction)
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
