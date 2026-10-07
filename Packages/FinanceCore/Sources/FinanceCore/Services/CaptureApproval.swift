import Foundation
import SwiftData
import PDFKit
import ImageIO
import UniformTypeIdentifiers

public struct CaptureApprovalInput: Sendable {
    public var captureID: UUID
    public var contoID: UUID
    public var categoryID: UUID?
    public var amount: Decimal
    public var currency: String
    public var type: TransactionType
    public var date: Date
    public var note: String
    public var sourceText: String
    public var sourceName: String
    public var paymentConfirmed: Bool
    public var planned: Bool
    public var filename: String?
    public var contentType: String?
    public var document: Data?
    public init(captureID: UUID, contoID: UUID, categoryID: UUID? = nil, amount: Decimal, currency: String,
                type: TransactionType = .expense, date: Date = Date(), note: String = "", paymentConfirmed: Bool, sourceText: String = "", sourceName: String = "",
                filename: String? = nil, contentType: String? = nil, document: Data? = nil, planned: Bool = false) {
        self.captureID = captureID; self.contoID = contoID; self.categoryID = categoryID
        self.amount = amount; self.currency = currency; self.type = type; self.date = date
        self.note = note; self.paymentConfirmed = paymentConfirmed
        self.planned = planned
        self.sourceText = sourceText; self.sourceName = sourceName
        self.filename = filename; self.contentType = contentType; self.document = document
    }
}

@MainActor public enum CaptureApproval {
    public enum Failure: LocalizedError {
        case invalidAmount, invalidSelection, currencyMismatch, unconfirmedPayment, invalidDocument, invalidDate
        public var errorDescription: String? {
            switch self {
            case .invalidAmount: "Inserisci un importo positivo con i decimali previsti dalla valuta."
            case .invalidSelection: "Scegli un conto attivo e una categoria dello stesso libro."
            case .currencyMismatch: "La valuta della proposta deve coincidere con quella del libro. Per una spesa in valuta diversa usa il modulo del movimento."
            case .unconfirmedPayment: "Conferma che il pagamento o l’accredito sia già avvenuto."
            case .invalidDocument: "Il documento non è valido o supera 10 MB."
            case .invalidDate: "Un movimento già avvenuto richiede una data trascorsa; un pagamento pianificato richiede una data futura."
            }
        }
    }
    @discardableResult public static func approve(_ input: CaptureApprovalInput, in container: ModelContainer, now: Date = Date()) throws -> UUID {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let id = input.captureID
        if let receipt = try context.fetch(FetchDescriptor<CaptureApprovalReceipt>(predicate: #Predicate { $0.captureID == id })).first { return receipt.transactionID }
        guard input.planned ? !input.paymentConfirmed : input.paymentConfirmed else { throw Failure.unconfirmedPayment }
        guard input.amount > 0, !input.amount.isNaN,
              (try? CurrencyConversion.convert(input.amount, rate: 1, currency: input.currency)) == input.amount else { throw Failure.invalidAmount }
        guard input.date.timeIntervalSince1970.isFinite,
              input.planned ? input.date > now : input.date <= now else { throw Failure.invalidDate }
        let contoID = input.contoID
        guard input.type != .transfer,
              let conto = try context.fetch(FetchDescriptor<Conto>(predicate: #Predicate { $0.id == contoID })).first,
              conto.isActive == true, let book = conto.account, book.isActive == true else { throw Failure.invalidSelection }
        guard book.currency == input.currency else { throw Failure.currencyMismatch }
        var category: Category?
        if let categoryID = input.categoryID {
            category = try context.fetch(FetchDescriptor<Category>(predicate: #Predicate { $0.id == categoryID })).first
            guard category?.isActive == true, category?.account?.id == book.id, category?.fits(input.type) == true else { throw Failure.invalidSelection }
        }
        if let document = input.document {
            guard !document.isEmpty, document.count <= 10 * 1024 * 1024, input.filename != nil,
                  let type = input.contentType else { throw Failure.invalidDocument }
            if type == UTType.pdf.identifier {
                guard PDFDocument(data: document) != nil else { throw Failure.invalidDocument }
            } else {
                guard UTType(type)?.conforms(to: .image) == true,
                      let image = CGImageSourceCreateWithData(document as CFData, nil),
                      CGImageSourceGetCount(image) > 0 else { throw Failure.invalidDocument }
            }
        }
        let transaction = Transaction(amount: input.amount, type: input.type, date: input.date, transactionDescription: String(input.note.prefix(500)))
        transaction.externalID = "capture:\(id.uuidString)"
        if !input.sourceText.isEmpty { transaction.notes = "Fonte: \(String(input.sourceName.prefix(160)))\n\(String(input.sourceText.prefix(30_000)))" }
        if input.type == .expense { transaction.setFromConto(conto) } else { transaction.setToConto(conto) }
        transaction.setCategory(category)
        context.insert(transaction)
        if let data = input.document, let filename = input.filename, let contentType = input.contentType {
            let attachment = TransactionAttachment(filename: filename, contentType: contentType, data: data)
            attachment.transaction = transaction; transaction.attachments = [attachment]
            context.insert(attachment)
        }
        context.insert(CaptureApprovalReceipt(captureID: id, transactionID: transaction.id))
        do { try context.save() } catch { context.rollback(); throw error }
        return transaction.id
    }
}
