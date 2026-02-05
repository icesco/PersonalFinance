//
//  CSVImportModels.swift
//  Personal Finance
//
//  Created by Claude on 04/02/26.
//

import Foundation
import SwiftUI

// MARK: - CSV Field Definition

enum CSVField: String, CaseIterable, Identifiable {
    // General
    case transactionType = "Tipo"
    case amount = "Importo"
    case sourceCurrency = "Valuta di origine"
    case targetCurrency = "Valuta di destinazione"
    case exchangeRate = "Tasso di cambio"

    // Assignment
    case sourceAccount = "Conto (Da)"
    case targetAccount = "Conto (A)"
    case category = "Categoria"
    case payee = "Beneficiario"

    // Date
    case date = "Data"

    // Misc
    case notes = "Note"
    case description = "Descrizione"

    var id: String { rawValue }

    var isRequired: Bool {
        self == .amount || self == .date
    }

    var icon: String {
        switch self {
        case .transactionType: return "arrow.left.arrow.right"
        case .amount: return "eurosign"
        case .sourceCurrency, .targetCurrency: return "coloncurrencysign.circle"
        case .exchangeRate: return "percent"
        case .sourceAccount: return "building.columns"
        case .targetAccount: return "building.columns.fill"
        case .category: return "tag"
        case .payee: return "person"
        case .date: return "calendar"
        case .notes: return "note.text"
        case .description: return "text.alignleft"
        }
    }

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

    var section: CSVFieldSection {
        switch self {
        case .transactionType, .amount, .sourceCurrency, .targetCurrency, .exchangeRate:
            return .general
        case .sourceAccount, .targetAccount, .category, .payee:
            return .assignment
        case .date:
            return .dateTime
        case .notes, .description:
            return .misc
        }
    }

    static var bySection: [CSVFieldSection: [CSVField]] {
        Dictionary(grouping: allCases, by: \.section)
    }
}

// MARK: - CSV Field Section

enum CSVFieldSection: String, CaseIterable, Identifiable {
    case general = "Generale"
    case assignment = "Assegnazione"
    case dateTime = "Data e ora"
    case misc = "Varie"

    var id: String { rawValue }

    var fields: [CSVField] {
        CSVField.allCases.filter { $0.section == self }
    }
}

// MARK: - CSV Date Format

enum CSVDateFormat: String, CaseIterable, Identifiable {
    // ISO 8601 formats
    case iso8601 = "yyyy-MM-dd'T'HH:mm:ss"
    case iso8601Z = "yyyy-MM-dd'T'HH:mm:ssZ"
    case iso8601Offset = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
    case iso8601DateOnly = "yyyy-MM-dd"

    // US formats
    case usSlash = "MM/dd/yyyy HH:mm"
    case usDash = "MM-dd-yyyy HH:mm"
    case usDot = "MM.dd.yyyy HH:mm"
    case usSlashShort = "MM/dd/yy HH:mm"
    case usSlashDateOnly = "MM/dd/yyyy"

    // European formats
    case euSlash = "dd/MM/yyyy HH:mm"
    case euDash = "dd-MM-yyyy HH:mm"
    case euDot = "dd.MM.yyyy HH:mm"
    case euSlashShort = "dd/MM/yy HH:mm"
    case euSlashDateOnly = "dd/MM/yyyy"
    case euDashDateOnly = "dd-MM-yyyy"

    // Text formats
    case longWeekday = "EEEE, MMM d, yyyy"
    case shortWeekday = "EEEE, MMM d, yy"
    case monthYear = "MMMM yyyy"
    case shortMonth = "MMM d, yyyy"

    // RFC 2822
    case rfc2822 = "E, d MMM yyyy HH:mm:ss Z"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var example: String {
        let formatter = DateFormatter()
        formatter.dateFormat = rawValue
        formatter.locale = Locale(identifier: "it_IT")
        return formatter.string(from: Date())
    }

    func parse(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = rawValue
        formatter.locale = Locale(identifier: "it_IT")
        return formatter.date(from: string)
    }
}

// MARK: - Field Mapping

struct FieldMapping: Identifiable, Equatable {
    let id = UUID()
    let field: CSVField
    var csvColumnIndex: Int?
    var csvColumnName: String?

    var isAssigned: Bool {
        csvColumnIndex != nil
    }

    static func == (lhs: FieldMapping, rhs: FieldMapping) -> Bool {
        lhs.field == rhs.field && lhs.csvColumnIndex == rhs.csvColumnIndex
    }
}

// MARK: - Account Filter Configuration

struct CSVAccountFilter {
    var isMultiAccount: Bool = false
    var accountColumnIndex: Int?
    var accountColumnName: String?
    var selectedAccountValue: String?
}

// MARK: - Account Value with Row Count

struct CSVAccountValue: Identifiable, Hashable {
    let id = UUID()
    let value: String
    let rowCount: Int
}

// MARK: - Import Options

struct CSVImportOptions {
    var dateFormat: CSVDateFormat = .iso8601Offset
    var ignoreZeroAmounts: Bool = false
    var ignoreDuplicates: Bool = true
    var createMissingCategories: Bool = true
    var createMissingConti: Bool = false
    var defaultContoId: UUID?

    // CSV parsing options
    var delimiter: Character = ","
    var hasHeader: Bool = true
    var encoding: String.Encoding = .utf8

    // Account filter options
    var accountFilter: CSVAccountFilter = CSVAccountFilter()
}

// MARK: - Parse Result

struct CSVParseResult {
    let headers: [String]
    let rows: [[String]]

    var rowCount: Int { rows.count }
    var columnCount: Int { headers.count }

    func value(row: Int, column: Int) -> String? {
        guard row < rows.count, column < rows[row].count else { return nil }
        return rows[row][column]
    }

    func value(row: Int, header: String) -> String? {
        guard let columnIndex = headers.firstIndex(of: header) else { return nil }
        return value(row: row, column: columnIndex)
    }
}

// MARK: - Import Result

struct CSVImportResult {
    let totalRows: Int
    let importedCount: Int
    let skippedCount: Int
    let errorCount: Int
    let errors: [ImportError]
    let duplicatesSkipped: Int
    let zeroAmountsSkipped: Int

    var successRate: Double {
        guard totalRows > 0 else { return 0 }
        return Double(importedCount) / Double(totalRows)
    }
}

// MARK: - Import Error

struct ImportError: Identifiable {
    let id = UUID()
    let rowNumber: Int
    let message: String
    let field: CSVField?
    let rawValue: String?
}

// MARK: - Validation Error

struct ValidationError: Identifiable {
    let id = UUID()
    let field: CSVField
    let message: String
}

// MARK: - Preview Row

struct CSVPreviewRow: Identifiable {
    let id = UUID()
    let rowNumber: Int
    let date: Date?
    let amount: Decimal?
    let type: String?
    let category: String?
    let conto: String?
    let description: String?
    let hasError: Bool
    let errorMessage: String?
}

// MARK: - Export Options

struct CSVExportOptions {
    var includeHeader: Bool = true
    var dateFormat: CSVDateFormat = .iso8601Offset
    var delimiter: String = ","
    var includeFields: Set<CSVField> = Set(CSVField.allCases)
    var dateFrom: Date?
    var dateTo: Date?
    var contoIds: Set<UUID> = []
    var encoding: String.Encoding = .utf8
}
