//
//  AppStateManager.swift
//  Personal Finance
//
//  Created by Claude on 24/08/25.
//

import SwiftUI
import SwiftData
import FinanceCore

// MARK: - Dashboard Style

enum DashboardStyle: String, CaseIterable, Codable {
    case classic = "classic"
    case crypto = "crypto"

    var displayName: String {
        switch self {
        case .classic: return "Classico"
        case .crypto: return "Moderno"
        }
    }
}

/// Main application state manager using @Observable
/// Handles tab selection, account management, and modal presentation
@Observable
final class AppStateManager {
    // MARK: - Tab Navigation
    var selectedTab: AppTab = .dashboard

    // MARK: - Dashboard Style
    var dashboardStyle: DashboardStyle = .classic {
        didSet {
            saveDashboardStyle()
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
            if let accountID = selectedAccount?.id.uuidString {
                UserDefaults.standard.set(accountID, forKey: "selectedAccountID")
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
            UserDefaults.standard.set(showAllAccounts, forKey: "showAllAccounts")
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
            if let contoID = selectedConto?.id.uuidString {
                UserDefaults.standard.set(contoID, forKey: "selectedContoID")
            } else {
                UserDefaults.standard.removeObject(forKey: "selectedContoID")
            }
        }
    }

    /// When true, shows all conti within the selected libro
    var showAllConti: Bool = true {
        didSet {
            UserDefaults.standard.set(showAllConti, forKey: "showAllConti")
        }
    }
    
    // MARK: - Modal States
    var showingAccountSelection = false
    var showingQuickTransaction = false
    var showingAccountCreation = false
    var showingOnboarding = false

    // MARK: - Quick Transaction Context
    var quickTransactionType: TransactionType = .expense

    // MARK: - Navigation Context
    var navigationRouter = NavigationRouter()

    // MARK: - Theme Management
    var themeManager = ThemeManager()

    // MARK: - Experience Level Management
    var experienceLevelManager = ExperienceLevelManager()

    // MARK: - Onboarding
    var hasCompletedOnboarding: Bool {
        get {
            UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "hasCompletedOnboarding")
        }
    }

    init() {
        loadDashboardStyle()
        loadShowAllAccounts()
        loadShowAllConti()
        loadSelectedAccount()
        checkOnboardingStatus()
    }

    private func loadDashboardStyle() {
        if let savedStyle = UserDefaults.standard.string(forKey: "dashboardStyle"),
           let style = DashboardStyle(rawValue: savedStyle) {
            dashboardStyle = style
        }
    }

    private func saveDashboardStyle() {
        UserDefaults.standard.set(dashboardStyle.rawValue, forKey: "dashboardStyle")
    }

    private func loadShowAllAccounts() {
        showAllAccounts = UserDefaults.standard.bool(forKey: "showAllAccounts")
    }

    private func loadShowAllConti() {
        // Default to true if not set
        if UserDefaults.standard.object(forKey: "showAllConti") == nil {
            showAllConti = true
        } else {
            showAllConti = UserDefaults.standard.bool(forKey: "showAllConti")
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
    }
    
    // MARK: - Account Management

    func selectAccount(_ account: Account) {
        showAllAccounts = false
        selectedAccount = account
        dismissAccountSelection()
    }

    func selectAllAccounts() {
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
        guard selectedAccount == nil else { return }
        
        // Try to load from UserDefaults
        if let savedAccountID = UserDefaults.standard.string(forKey: "selectedAccountID"),
           let uuid = UUID(uuidString: savedAccountID),
           let accounts = accounts,
           let account = accounts.first(where: { $0.id == uuid }) {
            selectedAccount = account
            return
        }
        
        // If no saved account or accounts array not provided, we'll need to show selection
        if accounts?.isEmpty == false {
            selectedAccount = accounts?.first
        }
    }
    
    func requiresAccountSelection(accounts: [Account]) -> Bool {
        if accounts.isEmpty {
            return false // Will show account creation instead
        }
        return selectedAccount == nil
    }
    
    // MARK: - Modal Management
    
    func presentAccountSelection() {
        showingAccountSelection = true
    }
    
    func dismissAccountSelection() {
        showingAccountSelection = false
    }
    
    func presentQuickTransaction(type: TransactionType = .expense) {
        quickTransactionType = type
        showingQuickTransaction = true
    }
    
    func dismissQuickTransaction() {
        showingQuickTransaction = false
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

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .transactions: return "Transazioni"
        case .settings: return "Impostazioni"
        case .addTransaction: return "Aggiungi"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "house"
        case .transactions: return "list.bullet.rectangle"
        case .settings: return "gearshape"
        case .addTransaction: return "plus.circle.fill"
        }
    }

    var selectedIcon: String {
        switch self {
        case .dashboard: return "house.fill"
        case .transactions: return "list.bullet.rectangle.fill"
        case .settings: return "gearshape.fill"
        case .addTransaction: return "plus.circle.fill"
        }
    }
}