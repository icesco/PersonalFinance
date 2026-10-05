import Foundation
#if !os(watchOS)
import FinanceCore
#endif

struct WatchOption: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
}

struct WatchBook: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let currency: String
    let monthSpent: Decimal
    let budgetName: String?
    let budgetRemaining: Decimal?
    let upcomingCount: Int
    var conti: [WatchOption]? = nil
    var categories: [WatchOption]? = nil
}

struct WatchOverview: Codable, Equatable, Sendable {
    var version = 1
    let generatedAt: Date
    let validUntil: Date
    let books: [WatchBook]
    let hidden: Bool
    static var redacted: Self { Self(generatedAt: Date(), validUntil: .distantPast, books: [], hidden: true) }
    func usable(at date: Date) -> Bool { version == 1 && !hidden && date < validUntil }
}

struct WatchExpenseDraft: Codable, Equatable, Sendable {
    let id: UUID
    let bookID: UUID?
    let amount: String
    let note: String

    var normalizedAmount: String? {
        guard amount.count <= 29,
              amount.range(of: #"^[0-9]+([.,][0-9]+)?$"#, options: .regularExpression) != nil,
              let value = Decimal(string: amount.replacingOccurrences(of: ",", with: ".")),
              value > 0, !value.isNaN, note.count <= 200 else { return nil }
        return amount.replacingOccurrences(of: ".", with: ",")
    }
}

struct WatchRequest: Codable, Sendable {
    var version = 1
    let draft: WatchExpenseDraft?
    var expense: RemoteExpenseInput? = nil
    var confirmation: RemoteExpenseQuote? = nil
}
struct WatchReply: Codable, Sendable {
    enum Status: String, Codable { case accepted, busy, invalid, overview, preview, saved, changed, unavailable }
    let status: Status
    let overview: WatchOverview?
    var quote: RemoteExpenseQuote? = nil
    var result: RemoteExpenseSaveResult? = nil
    var message: String? = nil
}
