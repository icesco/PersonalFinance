import Foundation
import SwiftData
import CryptoKit

@MainActor
public enum FormiCLIAccountSplitService {
    public static func execute(_ request: FormiCLIRequest, container: ModelContainer) throws -> [String: Any] {
        guard request.version == 4, request.command == "account-split", request.movements.isEmpty,
              request.categoryMutation == nil, request.transactionQuery == nil,
              let plan = request.accountSplit, plan.sourceAccountID != plan.destinationAccountID,
              !plan.transactionIDs.isEmpty, plan.transactionIDs.count <= 500,
              Set(plan.transactionIDs).count == plan.transactionIDs.count,
              !plan.sourceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !plan.destinationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              plan.sourceName.count <= 200, plan.destinationName.count <= 200 else {
            throw FormiCLIService.Failure("Piano di separazione non valido.")
        }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        do {
            let accounts = try context.fetch(FetchDescriptor<Conto>())
            guard let source = accounts.first(where: { $0.id == plan.sourceAccountID && $0.isActive == true }),
                  let book = source.account, book.isActive == true, source.type == .credit,
                  !(try context.fetch(FetchDescriptor<SharedBookMembership>())).contains(where: { $0.localBookID == book.id }) else {
                throw FormiCLIService.Failure("Scegli una carta attiva in un libro personale.")
            }
            let existing = accounts.first { $0.id == plan.destinationAccountID }
            if let existing {
                guard existing.account?.id == book.id, existing.isActive == true,
                      existing.type == .credit, existing.name == plan.destinationName else {
                    throw FormiCLIService.Failure("Il conto di destinazione non corrisponde al piano.")
                }
            }
            let all = try context.fetch(FetchDescriptor<Transaction>())
            let selected = all.filter { plan.transactionIDs.contains($0.id) }.sorted { $0.id.uuidString < $1.id.uuidString }
            guard selected.count == plan.transactionIDs.count else { throw FormiCLIService.Failure("Movimenti mancanti: rileggi il registro.") }
            func touches(_ row: Transaction, _ id: UUID) -> Bool {
                (row.fromConto?.id ?? row.fromContoId) == id || (row.toConto?.id ?? row.toContoId) == id
            }
            if existing != nil, selected.allSatisfy({ touches($0, plan.destinationAccountID) && !touches($0, source.id) }) {
                return ["saved": false, "alreadyRecorded": true, "destinationAccountID": plan.destinationAccountID.uuidString,
                        "transactionIDs": selected.map { $0.id.uuidString }]
            }
            guard existing == nil, selected.allSatisfy({ touches($0, source.id) && !touches($0, plan.destinationAccountID) }),
                  selected.allSatisfy({ $0.isRecurring != true && $0.recurrenceSourceID == nil }) else {
                throw FormiCLIService.Failure("Il piano richiede movimenti non ricorrenti ancora nel conto di origine.")
            }
            for row in selected {
                for account in [row.fromConto, row.toConto].compactMap({ $0 }) {
                    guard account.account?.id == book.id else { throw FormiCLIService.Failure("I movimenti devono restare nello stesso libro.") }
                }
            }
            let fingerprints = selected.map { row in
                "\(row.id)|\(row.updatedAt?.timeIntervalSince1970 ?? 0)|\(row.amount ?? 0)|\(row.date.timeIntervalSince1970)|\((row.fromConto?.id ?? row.fromContoId)?.uuidString ?? "nil")|\((row.toConto?.id ?? row.toContoId)?.uuidString ?? "nil")"
            }
            let payload = [source.name ?? "", plan.sourceName, plan.destinationName, plan.destinationAccountID.uuidString] + fingerprints
            let revision = SHA256.hash(data: try JSONEncoder().encode(payload)).map { String(format: "%02x", $0) }.joined()
            let summary: [String: Any] = ["saved": request.commit, "alreadyRecorded": false,
                "revision": revision, "sourceAccountID": source.id.uuidString,
                "sourceName": plan.sourceName, "destinationAccountID": plan.destinationAccountID.uuidString,
                "destinationName": plan.destinationName, "transactionIDs": selected.map { $0.id.uuidString },
                "movements": selected.map { row -> [String: String] in
                    ["id": row.id.uuidString, "amount": "\(row.amount ?? 0)", "description": row.transactionDescription ?? "",
                     "type": row.type.rawValue]
                }]
            guard request.commit else { return summary }
            guard plan.revision == revision else { throw FormiCLIService.Failure("Anteprima cambiata: ripeti prima senza --yes.") }
            let destination = Conto(name: plan.destinationName, type: .credit, initialBalance: 0)
            destination.id = plan.destinationAccountID
            destination.account = book
            context.insert(destination)
            source.name = plan.sourceName
            source.updatedAt = .now
            for row in selected {
                if (row.fromConto?.id ?? row.fromContoId) == source.id { row.setFromConto(destination) }
                if (row.toConto?.id ?? row.toContoId) == source.id { row.setToConto(destination) }
                row.updatedAt = .now
            }
            try context.save()
            return summary
        } catch {
            context.rollback()
            throw error
        }
    }
}
