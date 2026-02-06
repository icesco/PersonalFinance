//
//  CSVModels.swift
//  FinanceCore
//
//  Pure CSV model types with no SwiftUI dependency.
//

import Foundation

// MARK: - CSV Field Definition

public enum CSVField: String, CaseIterable, Identifiable, Sendable {
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

    public var id: String { rawValue }

    public var isRequired: Bool {
        self == .amount || self == .date
    }

    public var icon: String {
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

    public var section: CSVFieldSection {
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

    public static var bySection: [CSVFieldSection: [CSVField]] {
        Dictionary(grouping: allCases, by: \.section)
    }
}

// MARK: - CSV Field Section

public enum CSVFieldSection: String, CaseIterable, Identifiable, Sendable {
    case general = "Generale"
    case assignment = "Assegnazione"
    case dateTime = "Data e ora"
    case misc = "Varie"

    public var id: String { rawValue }

    public var fields: [CSVField] {
        CSVField.allCases.filter { $0.section == self }
    }
}

// MARK: - CSV Date Format

public enum CSVDateFormat: String, CaseIterable, Identifiable, Sendable {
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

    public var id: String { rawValue }

    public var displayName: String { rawValue }

    /// Preferred fallback order: EU formats first (Italian app), then ISO, then US
    public static let fallbackOrder: [CSVDateFormat] = [
        // European (most likely for Italian users)
        .euSlashDateOnly, .euDashDateOnly, .euSlash, .euDash, .euDot, .euSlashShort,
        // ISO 8601
        .iso8601DateOnly, .iso8601, .iso8601Z, .iso8601Offset,
        // US
        .usSlashDateOnly, .usSlash, .usDash, .usDot, .usSlashShort,
        // Text / other
        .longWeekday, .shortWeekday, .monthYear, .shortMonth, .rfc2822,
    ]

    public var example: String {
        let formatter = DateFormatter()
        formatter.dateFormat = rawValue
        formatter.locale = Locale(identifier: "it_IT")
        return formatter.string(from: Date())
    }

    public func parse(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = rawValue
        formatter.locale = Locale(identifier: "it_IT")
        return formatter.date(from: string)
    }
}

// MARK: - Field Mapping

public struct FieldMapping: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let field: CSVField
    public var csvColumnIndex: Int?
    public var csvColumnName: String?

    public var isAssigned: Bool {
        csvColumnIndex != nil
    }

    public init(field: CSVField, csvColumnIndex: Int? = nil, csvColumnName: String? = nil) {
        self.id = UUID()
        self.field = field
        self.csvColumnIndex = csvColumnIndex
        self.csvColumnName = csvColumnName
    }

    public static func == (lhs: FieldMapping, rhs: FieldMapping) -> Bool {
        lhs.field == rhs.field && lhs.csvColumnIndex == rhs.csvColumnIndex
    }
}

// MARK: - Account Filter Configuration

public struct CSVAccountFilter: Sendable {
    public var isMultiAccount: Bool
    public var accountColumnIndex: Int?
    public var accountColumnName: String?
    public var selectedAccountValue: String?

    public init(
        isMultiAccount: Bool = false,
        accountColumnIndex: Int? = nil,
        accountColumnName: String? = nil,
        selectedAccountValue: String? = nil
    ) {
        self.isMultiAccount = isMultiAccount
        self.accountColumnIndex = accountColumnIndex
        self.accountColumnName = accountColumnName
        self.selectedAccountValue = selectedAccountValue
    }
}

// MARK: - Account Value with Row Count

public struct CSVAccountValue: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let value: String
    public let rowCount: Int

    public init(value: String, rowCount: Int) {
        self.id = UUID()
        self.value = value
        self.rowCount = rowCount
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(value)
        hasher.combine(rowCount)
    }

    public static func == (lhs: CSVAccountValue, rhs: CSVAccountValue) -> Bool {
        lhs.value == rhs.value && lhs.rowCount == rhs.rowCount
    }
}

// MARK: - Import Options

public struct CSVImportOptions: Sendable {
    public var dateFormat: CSVDateFormat
    public var ignoreZeroAmounts: Bool
    public var ignoreDuplicates: Bool
    public var createMissingCategories: Bool
    public var createMissingConti: Bool
    public var defaultContoId: UUID?

    // CSV parsing options
    public var delimiter: Character
    public var hasHeader: Bool
    public var encoding: String.Encoding

    // Account filter options
    public var accountFilter: CSVAccountFilter

    public init(
        dateFormat: CSVDateFormat = .euSlashDateOnly,
        ignoreZeroAmounts: Bool = false,
        ignoreDuplicates: Bool = true,
        createMissingCategories: Bool = true,
        createMissingConti: Bool = false,
        defaultContoId: UUID? = nil,
        delimiter: Character = ",",
        hasHeader: Bool = true,
        encoding: String.Encoding = .utf8,
        accountFilter: CSVAccountFilter = CSVAccountFilter()
    ) {
        self.dateFormat = dateFormat
        self.ignoreZeroAmounts = ignoreZeroAmounts
        self.ignoreDuplicates = ignoreDuplicates
        self.createMissingCategories = createMissingCategories
        self.createMissingConti = createMissingConti
        self.defaultContoId = defaultContoId
        self.delimiter = delimiter
        self.hasHeader = hasHeader
        self.encoding = encoding
        self.accountFilter = accountFilter
    }
}

// MARK: - Parse Result

public struct CSVParseResult: Sendable {
    public let headers: [String]
    public let rows: [[String]]

    public var rowCount: Int { rows.count }
    public var columnCount: Int { headers.count }

    public init(headers: [String], rows: [[String]]) {
        self.headers = headers
        self.rows = rows
    }

    public func value(row: Int, column: Int) -> String? {
        guard row < rows.count, column < rows[row].count else { return nil }
        return rows[row][column]
    }

    public func value(row: Int, header: String) -> String? {
        guard let columnIndex = headers.firstIndex(of: header) else { return nil }
        return value(row: row, column: columnIndex)
    }
}

// MARK: - Import Result

public struct CSVImportResult: Sendable {
    public let totalRows: Int
    public let importedCount: Int
    public let skippedCount: Int
    public let errorCount: Int
    public let errors: [ImportError]
    public let duplicatesSkipped: Int
    public let zeroAmountsSkipped: Int

    public var successRate: Double {
        guard totalRows > 0 else { return 0 }
        return Double(importedCount) / Double(totalRows)
    }

    public init(
        totalRows: Int,
        importedCount: Int,
        skippedCount: Int,
        errorCount: Int,
        errors: [ImportError],
        duplicatesSkipped: Int,
        zeroAmountsSkipped: Int
    ) {
        self.totalRows = totalRows
        self.importedCount = importedCount
        self.skippedCount = skippedCount
        self.errorCount = errorCount
        self.errors = errors
        self.duplicatesSkipped = duplicatesSkipped
        self.zeroAmountsSkipped = zeroAmountsSkipped
    }
}

// MARK: - Import Error

public struct ImportError: Identifiable, Sendable {
    public let id: UUID
    public let rowNumber: Int
    public let message: String
    public let field: CSVField?
    public let rawValue: String?

    public init(rowNumber: Int, message: String, field: CSVField?, rawValue: String?) {
        self.id = UUID()
        self.rowNumber = rowNumber
        self.message = message
        self.field = field
        self.rawValue = rawValue
    }
}

// MARK: - Validation Error

public struct ValidationError: Identifiable, Sendable {
    public let id: UUID
    public let field: CSVField
    public let message: String

    public init(field: CSVField, message: String) {
        self.id = UUID()
        self.field = field
        self.message = message
    }
}

// MARK: - Preview Row

public struct CSVPreviewRow: Identifiable, Sendable {
    public let id: UUID
    public let rowNumber: Int
    public let date: Date?
    public let amount: Decimal?
    public let type: String?
    public let category: String?
    public let conto: String?
    public let description: String?
    public let hasError: Bool
    public let errorMessage: String?

    public init(
        rowNumber: Int,
        date: Date?,
        amount: Decimal?,
        type: String?,
        category: String?,
        conto: String?,
        description: String?,
        hasError: Bool,
        errorMessage: String?
    ) {
        self.id = UUID()
        self.rowNumber = rowNumber
        self.date = date
        self.amount = amount
        self.type = type
        self.category = category
        self.conto = conto
        self.description = description
        self.hasError = hasError
        self.errorMessage = errorMessage
    }
}

// MARK: - Export Options

public struct CSVExportOptions: Sendable {
    public var includeHeader: Bool
    public var dateFormat: CSVDateFormat
    public var delimiter: String
    public var includeFields: Set<CSVField>
    public var dateFrom: Date?
    public var dateTo: Date?
    public var contoIds: Set<UUID>
    public var encoding: String.Encoding

    public init(
        includeHeader: Bool = true,
        dateFormat: CSVDateFormat = .iso8601Offset,
        delimiter: String = ",",
        includeFields: Set<CSVField> = Set(CSVField.allCases),
        dateFrom: Date? = nil,
        dateTo: Date? = nil,
        contoIds: Set<UUID> = [],
        encoding: String.Encoding = .utf8
    ) {
        self.includeHeader = includeHeader
        self.dateFormat = dateFormat
        self.delimiter = delimiter
        self.includeFields = includeFields
        self.dateFrom = dateFrom
        self.dateTo = dateTo
        self.contoIds = contoIds
        self.encoding = encoding
    }
}

// MARK: - Import Row Error

public enum ImportRowError: LocalizedError, Sendable {
    case missingRequiredField(CSVField)
    case invalidAmount(String)
    case invalidDate(String)
    case contoNotFound(String)
    case categoryNotFound(String)

    public var field: CSVField? {
        switch self {
        case .missingRequiredField(let field): return field
        case .invalidAmount: return .amount
        case .invalidDate: return .date
        case .contoNotFound: return .sourceAccount
        case .categoryNotFound: return .category
        }
    }

    public var rawValue: String? {
        switch self {
        case .missingRequiredField: return nil
        case .invalidAmount(let value): return value
        case .invalidDate(let value): return value
        case .contoNotFound(let value): return value
        case .categoryNotFound(let value): return value
        }
    }

    public var errorDescription: String? {
        switch self {
        case .missingRequiredField(let field):
            return "Campo obbligatorio mancante: \(field.rawValue)"
        case .invalidAmount(let value):
            return "Importo non valido: \(value)"
        case .invalidDate(let value):
            return "Data non valida: \(value)"
        case .contoNotFound(let name):
            return "Conto non trovato: \(name)"
        case .categoryNotFound(let name):
            return "Categoria non trovata: \(name)"
        }
    }
}
