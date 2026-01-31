//
//  WidgetDataProvider.swift
//  FinanceCore
//
//  Created by Francesco Bianco on 24/08/25.
//

import Foundation
import SwiftData

/// Widget-specific data provider for cross-process data access
public actor WidgetDataProvider {
    public static let shared = WidgetDataProvider()

    private let appGroupIdentifier: String
    private var container: ModelContainer?

    public init(appGroupIdentifier: String = FinanceCoreModule.defaultAppGroupIdentifier) {
        self.appGroupIdentifier = appGroupIdentifier
    }

    // MARK: - Container Management

    private func getContainer() throws -> ModelContainer {
        if let container = container {
            return container
        }

        let newContainer = try FinanceCoreModule.widgetModelContainer(
            appGroupIdentifier: appGroupIdentifier
        )
        container = newContainer
        return newContainer
    }
    
    // MARK: - Data Access Methods
    
    /// Fetch account summaries for widget display
    public func fetchAccountSummaries() throws -> [AccountSummary] {
        let container = try getContainer()
        let context = ModelContext(container)
        
        let descriptor = FetchDescriptor<Account>(
            predicate: #Predicate<Account> { $0.isActive == true },
            sortBy: [SortDescriptor(\Account.name)]
        )

        let accounts = try context.fetch(descriptor)

        return accounts.map { account in
            AccountSummary(
                id: account.persistentModelID,
                name: account.name ?? "",
                currency: account.currency ?? "EUR",
                totalBalance: account.totalBalance,
                accountCount: account.conti?.count ?? 0
            )
        }
    }
    
    /// Fetch recent transactions for widget display
    public func fetchRecentTransactions(limit: Int = 5) throws -> [TransactionSummary] {
        let container = try getContainer()
        let context = ModelContext(container)
        
        var descriptor = FetchDescriptor<Transaction>(
            sortBy: [SortDescriptor(\Transaction.date, order: .reverse)]
        )
        descriptor.fetchLimit = limit

        let transactions = try context.fetch(descriptor)

        return transactions.compactMap { transaction in
            guard let conto = transaction.fromConto ?? transaction.toConto else { return nil }
            
            return TransactionSummary(
                id: transaction.persistentModelID,
                amount: transaction.amount ?? 0,
                description: transaction.transactionDescription ?? "",
                date: transaction.date ?? Date(),
                type: transaction.type ?? .expense,
                contoName: conto.name ?? "",
                categoryName: transaction.category?.name
            )
        }
    }
    
    /// Fetch total balance across all accounts
    public func fetchTotalBalance() throws -> Decimal {
        let summaries = try fetchAccountSummaries()
        return summaries.reduce(0) { $0 + $1.totalBalance }
    }
    
    /// Fetch account balance for specific account ID
    public func fetchAccountBalance(for accountId: PersistentIdentifier) throws -> Decimal? {
        let container = try getContainer()
        let context = ModelContext(container)
        
        guard let account = context.model(for: accountId) as? Account else {
            return nil
        }
        
        return account.totalBalance
    }
}

// MARK: - Widget Data Models

/// Lightweight account summary for widget display
public struct AccountSummary: Identifiable, Codable, Hashable, Sendable {
    public let id: PersistentIdentifier
    public let name: String
    public let currency: String
    public let totalBalance: Decimal
    public let accountCount: Int
    
    public init(id: PersistentIdentifier, name: String, currency: String, totalBalance: Decimal, accountCount: Int) {
        self.id = id
        self.name = name
        self.currency = currency
        self.totalBalance = totalBalance
        self.accountCount = accountCount
    }
}

/// Lightweight transaction summary for widget display
public struct TransactionSummary: Identifiable, Codable, Hashable, Sendable {
    public let id: PersistentIdentifier
    public let amount: Decimal
    public let description: String
    public let date: Date
    public let type: TransactionType
    public let contoName: String
    public let categoryName: String?
    
    public init(id: PersistentIdentifier, amount: Decimal, description: String, date: Date, type: TransactionType, contoName: String, categoryName: String?) {
        self.id = id
        self.amount = amount
        self.description = description
        self.date = date
        self.type = type
        self.contoName = contoName
        self.categoryName = categoryName
    }
}

// MARK: - Widget Configuration

/// Configuration for widget data refresh
public struct WidgetConfiguration: Sendable {
    public let refreshInterval: TimeInterval
    public let maxTransactions: Int
    public let showBalances: Bool
    
    public static let `default` = WidgetConfiguration(
        refreshInterval: 900, // 15 minutes
        maxTransactions: 5,
        showBalances: true
    )
    
    public init(refreshInterval: TimeInterval, maxTransactions: Int, showBalances: Bool) {
        self.refreshInterval = refreshInterval
        self.maxTransactions = maxTransactions
        self.showBalances = showBalances
    }
}