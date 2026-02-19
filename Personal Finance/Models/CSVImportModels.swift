//
//  CSVImportModels.swift
//  Personal Finance
//
//  SwiftUI extensions for FinanceCore CSV types.
//

import SwiftUI
import FinanceCore

extension CSVField {
    var iconColor: Color {
        switch self {
        case .transactionType: return .blue
        case .amount: return .green
        case .sourceCurrency, .targetCurrency, .exchangeRate: return .orange
        case .sourceAccount, .targetAccount: return .purple
        case .category: return .pink
        case .payee: return .cyan
        case .date: return .red
        case .notes, .description: return .gray
        }
    }
}
