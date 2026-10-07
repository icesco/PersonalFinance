//
//  AppStateManager.swift
//  Personal Finance
//
//  Created by Claude on 24/08/25.
//

import SwiftUI
import SwiftData
import FinanceCore

/// Main application state manager using @Observable
/// Handles tab selection, account management, and modal presentation
@Observable
final class AppStateManager {
    private let persistsSelection: Bool
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var pendingAccountID: UUID?
    @ObservationIgnored private var isRestoringSelection = false
    @ObservationIgnored private weak var refreshOrigin: AppStateManager?

    // MARK: - Tab Navigation
    var selectedTab: AppTab = .dashboard

    /// Tab roots currently on screen that want the new-transaction button; pushed screens drop out.
    var transactionButtonRoots: Set<AppTab> = []
    var showsTransactionButton: Bool { transactionButtonRoots.contains(selectedTab) }

    // MARK: - Tinted Backgrounds
    var tintedBackgrounds: Bool = true {
        didSet {
            guard persistsSelection && !isRestoringSelection else { return }
            defaults.set(tintedBackgrounds, forKey: "tintedBackgrounds")
        }
    }

    // MARK: - Data Refresh
    /// Incremented when data changes to trigger view updates
    var dataRefreshTrigger: Int = 0

    // MARK: - Libro Management (Account in data model)
    /// The selected Libro (top-level container)
    var selectedAccount: Account? {
        didSet {
            // Persist selected libro ID
            if persistsSelection && !isRestoringSelection {
                pendingAccountID = nil
                if let accountID = selectedAccount?.id.uuidString {
                    defaults.set(accountID, forKey: "selectedAccountID")
                } else {
                    defaults.removeObject(forKey: "selectedAccountID")
                }
            }
            // Reset conto selection when libro changes
            if selectedAccount != nil {
                selectedConto = nil
                showAllConti = true
            }
        }
    }

    /// When true, dashboard shows aggregated data from all libri
    var showAllAccounts: Bool = false {
        didSet {
            if persistsSelection {
                defaults.set(showAllAccounts, forKey: "showAllAccounts")
            }
            if showAllAccounts {
                selectedConto = nil
                showAllConti = true
            }
        }
    }

    // MARK: - Conto Management (Account in UI terminology)
    /// The selected Conto (individual account like credit card, bank account)
    var selectedConto: Conto? {
        didSet {
            guard persistsSelection && !isRestoringSelection else { return }
            if let contoID = selectedConto?.id.uuidString {
                defaults.set(contoID, forKey: "selectedContoID")
            } else {
                defaults.removeObject(forKey: "selectedContoID")
            }
        }
    }

    /// When true, shows all conti within the selected libro
    var showAllConti: Bool = true {
        didSet {
            guard persistsSelection && !isRestoringSelection else { return }
            defaults.set(showAllConti, forKey: "showAllConti")
        }
    }
    
    // MARK: - Modal States
    var showingSettingsWindow = false
    var showingAccountSelection = false
    var watchDraftID: UUID?
    var showingQuickTransaction = false
    var showingTransferSheet = false
    var showingAccountCreation = false
    var showingOnboarding = false

    // MARK: - Quick Transaction Context
    var quickTransactionType: TransactionType = .expense
    var quickTransactionIsPlanned = false
    var quickTransactionPrefill: (amount: String, description: String)?

    // MARK: - Navigation Context
    var navigationRouter = NavigationRouter()

    // MARK: - Theme Management
    var themeManager = ThemeManager.shared

    // MARK: - Onboarding
    var hasCompletedOnboarding: Bool {
        get {
            defaults.bool(forKey: "hasCompletedOnboarding")
        }
        set {
            defaults.set(newValue, forKey: "hasCompletedOnboarding")
        }
    }

    init(persistsSelection: Bool = true, defaults: UserDefaults = .standard) {
        self.persistsSelection = persistsSelection
        self.defaults = defaults
        pendingAccountID = defaults.string(forKey: "selectedAccountID").flatMap(UUID.init(uuidString:))
        loadTintedBackgrounds()
        loadShowAllAccounts()
        loadShowAllConti()
        loadSelectedAccount()
        checkOnboardingStatus()
    }

    /// Each desktop task keeps its book and draft inputs while the main window remains navigable.
    func windowSnapshot() -> AppStateManager {
        let copy = AppStateManager(persistsSelection: false, defaults: defaults)
        copy.refreshOrigin = refreshOrigin ?? self
        copy.selectedAccount = selectedAccount
        copy.selectedConto = selectedConto
        copy.showAllAccounts = showAllAccounts
        copy.showAllConti = showAllConti
        copy.tintedBackgrounds = tintedBackgrounds
        copy.quickTransactionType = quickTransactionType
        copy.quickTransactionIsPlanned = quickTransactionIsPlanned
        copy.quickTransactionPrefill = quickTransactionPrefill
        return copy
    }

    private func loadTintedBackgrounds() {
        if defaults.object(forKey: "tintedBackgrounds") == nil {
            tintedBackgrounds = true
        } else {
            tintedBackgrounds = defaults.bool(forKey: "tintedBackgrounds")
        }
    }

    private func loadShowAllAccounts() {
        showAllAccounts = defaults.bool(forKey: "showAllAccounts")
    }

    private func loadShowAllConti() {
        // Default to true if not set
        if defaults.object(forKey: "showAllConti") == nil {
            showAllConti = true
        } else {
            showAllConti = defaults.bool(forKey: "showAllConti")
        }
    }

    private func checkOnboardingStatus() {
        if !hasCompletedOnboarding {
            showingOnboarding = true
        }
    }
    
    // MARK: - Tab Management

    func selectTab(_ tab: AppTab) {
        selectedTab = tab
    }

    // MARK: - Data Refresh

    /// Call when data changes to notify dependent views to refresh
    func triggerDataRefresh() {
        dataRefreshTrigger += 1
        refreshOrigin?.triggerDataRefresh()
    }
    
    // MARK: - Account Management

    func selectAccount(_ account: Account) {
        showAllAccounts = false
        selectedAccount = account
        dismissAccountSelection()
    }

    func selectAllAccounts() {
        pendingAccountID = nil
        showAllAccounts = true
        dismissAccountSelection()
    }

    // MARK: - Conto Selection

    func selectConto(_ conto: Conto) {
        showAllConti = false
        selectedConto = conto
    }

    func selectAllConti() {
        showAllConti = true
        selectedConto = nil
    }
    
    func loadSelectedAccount(from accounts: [Account]? = nil) {
        guard let accounts else { return }
        let activeAccounts = accounts.filter { $0.isActive == true }

        // A partially loaded (for example, iCloud) list must not overwrite the last choice.
        if let pendingAccountID,
           let account = activeAccounts.first(where: { $0.id == pendingAccountID }) {
            isRestoringSelection = true
            selectedAccount = account
            isRestoringSelection = false
            self.pendingAccountID = nil
            return
        }

        if let selectedAccount, activeAccounts.contains(where: { $0.id == selectedAccount.id }) {
            return
        }

        // Use an available book while waiting, retaining the saved ID for later query updates.
        isRestoringSelection = pendingAccountID != nil || activeAccounts.isEmpty
        selectedAccount = activeAccounts.first
        isRestoringSelection = false
    }

    func requiresAccountSelection(accounts: [Account]) -> Bool {
        !accounts.isEmpty && selectedAccount == nil && !showAllAccounts
    }

    // MARK: - Modal Management
    
    func presentAccountSelection() {
        showingAccountSelection = true
    }
    
    func dismissAccountSelection() {
        showingAccountSelection = false
    }
    
    func presentQuickTransaction(type: TransactionType = .expense, planned: Bool = false) {
        quickTransactionPrefill = nil
        quickTransactionType = type
        quickTransactionIsPlanned = planned
        showingQuickTransaction = true
    }

    @MainActor
    func dismissQuickTransaction() {
        if let id = watchDraftID { WatchDraftMailbox.shared.delivered(id) }
        watchDraftID = nil
        showingQuickTransaction = false
        quickTransactionPrefill = nil
    }

    func dismissTransferSheet() {
        showingTransferSheet = false
    }
    
    func presentAccountCreation() {
        showingAccountCreation = true
    }
    
    func dismissAccountCreation() {
        showingAccountCreation = false
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        showingOnboarding = false
    }

    func dismissOnboarding() {
        showingOnboarding = false
    }

    func resetOnboarding() {
        hasCompletedOnboarding = false
        showingOnboarding = true
        selectedAccount = nil
    }

    // MARK: - Account Data
    
    func activeConti(for account: Account?) -> [Conto] {
        guard let account = account else { return [] }
        return account.activeConti
    }
    
    func allTransactions(for account: Account?) -> [FinanceTransaction] {
        guard let account = account else { return [] }
        
        let allTransactions = account.activeConti.flatMap { conto in
            conto.allTransactions
        }
        
        return Array(Set(allTransactions)).sorted { 
            ($0.date ?? Date.distantPast) > ($1.date ?? Date.distantPast) 
        }
    }
}

// MARK: - App Tabs

enum AppTab: Int, CaseIterable {
    case dashboard = 0
    case transactions = 1
    case settings = 2
    case addTransaction = 3 // Used for legacy tab bar button
    case analysis = 4
    case planning = 5
    case search = 6 // Dedicated tab on iPad and Mac; lives inside Movimenti on iPhone

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .analysis: return "Analisi"
        case .planning: return "Pianifica"
        case .transactions: return "Transazioni"
        case .search: return "Cerca"
        case .settings: return "Impostazioni"
        case .addTransaction: return "Aggiungi"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "house"
        case .analysis: return "chart.pie"
        case .planning: return "calendar"
        case .transactions: return "list.bullet.rectangle"
        case .search: return "magnifyingglass"
        case .settings: return "gearshape"
        case .addTransaction: return "plus.circle.fill"
        }
    }

    var selectedIcon: String {
        switch self {
        case .dashboard: return "house.fill"
        case .analysis: return "chart.pie.fill"
        case .planning: return "calendar"
        case .transactions: return "list.bullet.rectangle.fill"
        case .search: return "magnifyingglass"
        case .settings: return "gearshape.fill"
        case .addTransaction: return "plus.circle.fill"
        }
    }
}
