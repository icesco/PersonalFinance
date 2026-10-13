import Foundation

/// Foundation-only wire format, also compiled into the bundled command-line client.
public struct FormiCLIRecurrence: Codable, Sendable, Equatable {
    public var frequency: String
    public var endDate: String?

    private enum CodingKeys: String, CodingKey { case frequency, endDate }
    private struct AnyKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    public init(from decoder: Decoder) throws {
        let keys = try decoder.container(keyedBy: AnyKey.self)
        if let unknown = keys.allKeys.first(where: { CodingKeys(rawValue: $0.stringValue) == nil }) {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Campo ricorrenza sconosciuto: \(unknown.stringValue)"))
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        frequency = try values.decode(String.self, forKey: .frequency)
        endDate = try values.decodeIfPresent(String.self, forKey: .endDate)
    }

    public init(frequency: String, endDate: String? = nil) {
        self.frequency = frequency
        self.endDate = endDate
    }
}

public struct FormiCLIMovement: Codable, Sendable, Equatable {
    public var requestID: UUID
    public var accountID: UUID
    public var categoryID: UUID?
    public var toAccountID: UUID?
    public var type: String
    /// Decimal string, never a floating-point JSON number.
    public var amount: String
    public var currency: String
    public var date: String
    public var description: String?
    public var recurrence: FormiCLIRecurrence?

    public init(requestID: UUID, accountID: UUID, categoryID: UUID? = nil,
                type: String = "expense", amount: String, currency: String,
                date: String, description: String? = nil, recurrence: FormiCLIRecurrence? = nil,
                toAccountID: UUID? = nil) {
        self.requestID = requestID; self.accountID = accountID; self.categoryID = categoryID
        self.type = type; self.amount = amount; self.currency = currency
        self.date = date; self.description = description; self.recurrence = recurrence
        self.toAccountID = toAccountID
    }
}

/// Omitted fields are preserved on update; parent="none" promotes to a root.
public struct FormiCLICategoryMutation: Codable, Sendable, Equatable {
    public var requestID: UUID
    public var categoryID: UUID?
    public var name: String?
    public var color: String?
    public var icon: String?
    public var parent: String?
    public var type: String?
    public var active: Bool?
    public var revision: String?

    public init(requestID: UUID, categoryID: UUID? = nil, name: String? = nil,
                color: String? = nil, icon: String? = nil, parent: String? = nil,
                type: String? = nil, active: Bool? = nil, revision: String? = nil) {
        self.requestID = requestID; self.categoryID = categoryID; self.name = name
        self.color = color; self.icon = icon; self.parent = parent; self.type = type
        self.active = active; self.revision = revision
    }
}

public struct FormiCLITransactionQuery: Codable, Sendable {
    public var accountID: UUID?
    public var from: String?
    public var to: String?
    public var limit: Int = 200
    public var offset: Int = 0
    public var includePlanned: Bool = false
    public var revision: String?

    public init(accountID: UUID? = nil, from: String? = nil, to: String? = nil,
                limit: Int = 200, offset: Int = 0, includePlanned: Bool = false, revision: String? = nil) {
        self.accountID = accountID; self.from = from; self.to = to
        self.limit = limit; self.offset = offset; self.includePlanned = includePlanned
        self.revision = revision
    }
}

public struct FormiCLIRequest: Codable, Sendable {
    public var accountSplit: FormiCLIAccountSplit?
    public var version: Int = 1
    public var id: UUID = UUID()
    public var issuedAt: Date = Date()
    public var command: String
    public var movements: [FormiCLIMovement] = []
    public var commit: Bool = false
    public var allowDuplicates: Bool = false
    public var categoryMutation: FormiCLICategoryMutation?
    public var transactionQuery: FormiCLITransactionQuery?
    public var includeArchived: Bool?
    public var bookID: UUID?
    /// The app must reject delivery to a different installed copy before any write.
    public var targetAppPath: String?
    public var targetConfiguration: String?

    public init(command: String, movements: [FormiCLIMovement] = [], commit: Bool = false,
                allowDuplicates: Bool = false, bookID: UUID? = nil) {
        self.command = command; self.movements = movements; self.commit = commit
        self.allowDuplicates = allowDuplicates; self.bookID = bookID
    }
}

public struct FormiCLIAccountSplit: Codable, Sendable {
    public var sourceAccountID: UUID
    public var destinationAccountID: UUID
    public var destinationName: String
    public var sourceName: String
    public var transactionIDs: [UUID]
    public var revision: String?
}

public enum FormiCLIWire {
    public static let enabledKey = "formi.cli.enabled"
    public static let requestType = "cc.fbianco.formi.cli.request"
    public static let responseType = "cc.fbianco.formi.cli.response"
    public static let maxBytes = 2_000_000
    /// Route to one installed copy without asking Launch Services to open a scene.
    public static func requestNotificationName(appPath: String, configuration: String) -> String {
        "cc.fbianco.formi.cli.request.\(configuration).\(Data(appPath.utf8).base64EncodedString())"
    }
    public static func pasteboardName(_ id: UUID) -> String { "cc.fbianco.formi.cli.\(id.uuidString)" }
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
