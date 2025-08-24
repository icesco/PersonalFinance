//
//  NavigationRouter.swift
//  Personal Finance
//
//  Created by Francesco Bianco on 24/08/25.
//

import SwiftUI
import SwiftData
import FinanceCore

/// Navigation destinations for type-safe routing
enum NavigationDestination: Hashable {
    case accountDetail(Account)
    case contoDetail(Conto)
    case createAccount
    case createConto(Account)
    case createTransaction(Conto, TransactionType)
    case createTransfer(Conto)
    case settings
}

/// Centralized navigation state management using @Observable
@Observable
final class NavigationRouter {
    /// Navigation path for the main NavigationStack
    var path = NavigationPath()
    
    /// Currently selected account (for main view state)
    var selectedAccount: Account?
    
    /// Sheet presentation states
    var isShowingAccountCreation = false
    var isShowingContoCreation = false
    var isShowingTransactionCreation = false
    var isShowingTransferSheet = false
    
    /// Current sheet context
    var accountForContoCreation: Account?
    var contoForTransactionCreation: Conto?
    var transactionType: TransactionType = .expense
    var contoForTransfer: Conto?
    
    init() {}
    
    // MARK: - Navigation Methods
    
    /// Navigate to account detail
    func navigateToAccountDetail(_ account: Account) {
        selectedAccount = account
        path.append(NavigationDestination.accountDetail(account))
    }
    
    /// Navigate to conto detail
    func navigateToContoDetail(_ conto: Conto) {
        path.append(NavigationDestination.contoDetail(conto))
    }
    
    /// Navigate to settings
    func navigateToSettings() {
        path.append(NavigationDestination.settings)
    }
    
    /// Navigate back to root
    func popToRoot() {
        path.removeLast(path.count)
    }
    
    /// Navigate back one level
    func pop() {
        if !path.isEmpty {
            path.removeLast()
        }
    }
    
    // MARK: - Sheet Presentation Methods
    
    /// Present account creation sheet
    func presentAccountCreation() {
        isShowingAccountCreation = true
    }
    
    /// Present conto creation sheet
    func presentContoCreation(for account: Account) {
        accountForContoCreation = account
        isShowingContoCreation = true
    }
    
    /// Present transaction creation sheet
    func presentTransactionCreation(for conto: Conto, type: TransactionType) {
        contoForTransactionCreation = conto
        transactionType = type
        isShowingTransactionCreation = true
    }
    
    /// Present transfer sheet
    func presentTransfer(from conto: Conto) {
        contoForTransfer = conto
        isShowingTransferSheet = true
    }
    
    /// Dismiss all sheets and reset sheet state
    func dismissSheets() {
        isShowingAccountCreation = false
        isShowingContoCreation = false
        isShowingTransactionCreation = false
        isShowingTransferSheet = false
        
        // Reset context
        accountForContoCreation = nil
        contoForTransactionCreation = nil
        contoForTransfer = nil
    }
    
    // MARK: - Deep Linking Support
    
    /// Navigate to specific account and conto
    func navigateToAccount(_ account: Account, conto: Conto? = nil) {
        selectedAccount = account
        path.append(NavigationDestination.accountDetail(account))
        
        if let conto = conto {
            path.append(NavigationDestination.contoDetail(conto))
        }
    }
    
    /// Set selected account without navigation (for initial state)
    func selectAccount(_ account: Account) {
        selectedAccount = account
    }
}

