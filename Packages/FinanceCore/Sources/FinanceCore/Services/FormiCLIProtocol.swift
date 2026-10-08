import Foundation

/// Foundation-only wire format, also compiled into the bundled command-line client.
public struct FormiCLIMovement: Codable, Sendable, Equatable {
    public var requestID: UUID
    public var accountID: UUID
    public var categoryID: UUID?
    public var type: String
    /// Decimal string, never a floating-point JSON number.
    public var amount: String
    public var currency: String
    public var date: String
    public var description: String?

    public init(requestID: UUID, accountID: UUID, categoryID: UUID? = nil,
                type: String = "expense", amount: String, currency: String,
                date: String, description: String? = nil) {
        self.requestID = requestID; self.accountID = accountID; self.categoryID = categoryID
        self.type = type; self.amount = amount; self.currency = currency
        self.date = date; self.description = description
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

public struct FormiCLIRequest: Codable, Sendable {
    public var version: Int = 1
    public var id: UUID = UUID()
    public var issuedAt: Date = Date()
    public var command: String
    public var movements: [FormiCLIMovement] = []
    public var commit: Bool = false
    public var allowDuplicates: Bool = false
    public var categoryMutation: FormiCLICategoryMutation?
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
