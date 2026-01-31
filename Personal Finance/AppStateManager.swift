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
    // MARK: - Tab Navigation
    var selectedTab: AppTab = .dashboard
    
    // MARK: - Account Management
    var selectedAccount: Account? {
        didSet {
            // Persist selected account ID
            if let accountID = selectedAccount?.id.uuidString {
                UserDefaults.standard.set(accountID, forKey: "selectedAccountID")
            }
        }
    }
    
    // MARK: - Modal States
    var showingAccountSelection = false
    var showingQuickTransaction = false
    var showingAccountCreation = false
    
    // MARK: - Quick Transaction Context
    var quickTransactionType: TransactionType = .expense
    
    // MARK: - Navigation Context
    var navigationRouter = NavigationRouter()
    
    init() {
        loadSelectedAccount()
    }
    
    // MARK: - Tab Management
    
    func selectTab(_ tab: AppTab) {
        selectedTab = tab
    }
    
    // MARK: - Account Management
    
    func selectAccount(_ account: Account) {
        selectedAccount = account
        dismissAccountSelection()
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

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .transactions: return "Transazioni"
        case .settings: return "Impostazioni"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "house"
        case .transactions: return "list.bullet.rectangle"
        case .settings: return "gearshape"
        }
    }

    var selectedIcon: String {
        switch self {
        case .dashboard: return "house.fill"
        case .transactions: return "list.bullet.rectangle.fill"
        case .settings: return "gearshape.fill"
        }
    }
}