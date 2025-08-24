import Foundation
import SwiftData

public class DataIntegrityService {
    
    // MARK: - Simple Duplicate Detection
    
    /// Check for duplicate transactions before inserting
    public static func findDuplicateTransactions(
        amount: Decimal,
        date: Date,
        contoId: UUID?,
        type: TransactionType,
        in context: ModelContext,
        tolerance: TimeInterval = 300 // 5 minutes
    ) -> [Transaction] {
        let startDate = date.addingTimeInterval(-tolerance)
        let endDate = date.addingTimeInterval(tolerance)
        
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { transaction in
                transaction.amount == amount &&
                transaction.date! >= startDate &&
                transaction.date! <= endDate &&
                transaction.type == type
            }
        )
        
        do {
            let results = try context.fetch(descriptor)
            return results.filter { transaction in
                // Additional check for same conto
                if let contoId = contoId {
                    return transaction.fromConto?.id == contoId || transaction.toConto?.id == contoId
                }
                return true
            }
        } catch {
            print("Error checking duplicates: \(error)")
            return []
        }
    }
    
    /// Check for duplicate accounts by name and currency
    public static func findDuplicateAccounts(
        name: String,
        currency: String,
        in context: ModelContext
    ) -> [Account] {
        let descriptor = FetchDescriptor<Account>(
            predicate: #Predicate { account in
                account.name == name && account.currency == currency
            }
        )
        
        do {
            return try context.fetch(descriptor)
        } catch {
            print("Error checking duplicate accounts: \(error)")
            return []
        }
    }
    
    /// Check for duplicate conti within the same account
    public static func findDuplicateConti(
        name: String,
        type: ContoType,
        accountId: UUID,
        in context: ModelContext
    ) -> [Conto] {
        let descriptor = FetchDescriptor<Conto>(
            predicate: #Predicate { conto in
                conto.name == name &&
                conto.type == type &&
                conto.account?.id == accountId
            }
        )
        
        do {
            return try context.fetch(descriptor)
        } catch {
            print("Error checking duplicate conti: \(error)")
            return []
        }
    }
    
    /// Check for duplicate categories within the same account
    public static func findDuplicateCategories(
        name: String,
        accountId: UUID,
        in context: ModelContext
    ) -> [Category] {
        let descriptor = FetchDescriptor<Category>(
            predicate: #Predicate { category in
                category.name == name &&
                category.account?.id == accountId
            }
        )
        
        do {
            return try context.fetch(descriptor)
        } catch {
            print("Error checking duplicate categories: \(error)")
            return []
        }
    }
}

// MARK: - Model Extensions for Easy Duplicate Checking

extension Transaction {
    /// Check if this transaction is a potential duplicate
    public func isDuplicateOf(_ other: Transaction, tolerance: TimeInterval = 300) -> Bool {
        guard let myDate = self.date,
              let otherDate = other.date,
              let myAmount = self.amount,
              let otherAmount = other.amount else {
            return false
        }
        
        return myAmount == otherAmount &&
               abs(myDate.timeIntervalSince(otherDate)) <= tolerance &&
               self.type == other.type &&
               (self.fromConto?.id == other.fromConto?.id || 
                self.toConto?.id == other.toConto?.id)
    }
}

extension Account {
    /// Check if this account is equivalent to another
    public func isEquivalentTo(_ other: Account) -> Bool {
        return self.name?.lowercased() == other.name?.lowercased() &&
               self.currency == other.currency
    }
}

extension Conto {
    /// Check if this conto is equivalent to another within the same account
    public func isEquivalentTo(_ other: Conto) -> Bool {
        return self.name?.lowercased() == other.name?.lowercased() &&
               self.type == other.type &&
               self.account?.id == other.account?.id
    }
}