import Foundation
import SwiftData

public enum SavingsGoalStatus: String, CaseIterable, Codable {
    case active = "active"
    case completed = "completed"
    case paused = "paused"
    
    public var displayName: String {
        switch self {
        case .active: return "Attivo"
        case .completed: return "Completato"
        case .paused: return "In Pausa"
        }
    }
}

public enum SavingsGoalCategory: String, CaseIterable, Codable {
    case emergency = "emergency"
    case vacation = "vacation"
    case home = "home"
    case car = "car"
    case education = "education"
    case retirement = "retirement"
    case other = "other"
    
    public var displayName: String {
        switch self {
        case .emergency: return "Fondo di Emergenza"
        case .vacation: return "Vacanze"
        case .home: return "Casa"
        case .car: return "Auto"
        case .education: return "Educazione"
        case .retirement: return "Pensione"
        case .other: return "Altro"
        }
    }
    
    public var icon: String {
        switch self {
        case .emergency: return "shield.fill"
        case .vacation: return "airplane"
        case .home: return "house.fill"
        case .car: return "car.fill"
        case .education: return "graduationcap.fill"
        case .retirement: return "clock.fill"
        case .other: return "target"
        }
    }
}

@Model
public final class SavingsGoal: Identifiable {
    public var id: UUID = UUID()
    public var externalID: String = UUID().uuidString
    public var name: String?
    public var targetAmount: Decimal?
    public var currentAmount: Decimal?
    public var targetDate: Date?
    public var category: SavingsGoalCategory?
    public var status: SavingsGoalStatus?
    public var createdAt: Date?
    public var updatedAt: Date?
    public var goalDescription: String?
    public var isActive: Bool?
    
    public var account: Account?
    
    public init(
        name: String,
        targetAmount: Decimal,
        targetDate: Date? = nil,
        category: SavingsGoalCategory = .other,
        goalDescription: String? = nil
    ) {
        self.name = name
        self.targetAmount = targetAmount
        self.currentAmount = 0
        self.targetDate = targetDate
        self.category = category
        self.status = .active
        self.goalDescription = goalDescription
        self.createdAt = Date()
        self.updatedAt = Date()
        self.isActive = true
    }
    
    public var linkedConti: [Conto] {
        (account?.conti ?? []).filter { $0.type == .savings && $0.savingsGoalID == id }
    }

    public var fundedAmount: Decimal {
        guard !linkedConti.isEmpty else { return currentAmount ?? 0 }
        return linkedConti.reduce(0) { $0 + $1.savingsCapital(at: Date()) }
    }

    public var progressPercentage: Double {
        guard let target = targetAmount, target > 0 else { return 0.0 }
        let current = fundedAmount
        return max(0, min(Double(truncating: current as NSDecimalNumber) / Double(truncating: target as NSDecimalNumber), 1.0)) * 100
    }
    
    public var remainingAmount: Decimal {
        guard let target = targetAmount else { return 0 }
        let current = fundedAmount
        return max(target - current, 0)
    }
    
    public var isCompleted: Bool {
        guard let target = targetAmount else { return false }
        let current = fundedAmount
        return current >= target
    }
    
    public var daysUntilTarget: Int? {
        guard let targetDate = targetDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: targetDate).day
    }
    
    public func addProgress(amount: Decimal) {
        currentAmount = (currentAmount ?? 0) + amount
        updatedAt = Date()
        
        if isCompleted && status == .active {
            status = .completed
        }
    }
}
