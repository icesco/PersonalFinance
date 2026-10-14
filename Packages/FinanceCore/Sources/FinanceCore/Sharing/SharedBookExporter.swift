import Foundation
import SwiftData
import CryptoKit

public struct SharedBookExport: Sendable {
    public let bookID: UUID
    public let records: [SharedBookRecord]
    /// Attachment bytes travel as CKAssets, never as JSON fields in CKRecords.
    public let assets: [SharedRecordID: Data]
}

@MainActor
public enum SharedBookExporter {
    public enum Failure: Error { case missingBook, missingAttachment, duplicateIdentity, invalidBoundary }

    public static func export(bookID: UUID, contoID: UUID? = nil, container: ModelContainer) throws -> SharedBookExport {
        let context = ModelContext(container)
        guard let book = try context.fetch(FetchDescriptor<Account>(predicate: #Predicate { $0.id == bookID })).first else { throw Failure.missingBook }
        let conti = (book.conti ?? []).filter { contoID == nil || $0.id == contoID }
        guard contoID == nil || conti.count == 1 else { throw Failure.invalidBoundary }
        var categories = book.categories ?? []
        let contoIDs = Set(conti.map(\.id)), categoryIDs = Set(categories.map(\.id))
        let transactions = try context.fetch(FetchDescriptor<Transaction>()).filter { transaction in
            let fromHere = (transaction.fromContoId ?? transaction.fromConto?.id).map(contoIDs.contains) == true
            let toHere = (transaction.toContoId ?? transaction.toConto?.id).map(contoIDs.contains) == true
            switch transaction.type {
            case .expense: return fromHere
            case .income: return toHere
            case .transfer: return fromHere || toHere
            }
        }
        if let contoID { categories = categories.filter { $0.sharedContoID == contoID } }
        let sharedCategoryIDs = Set(categories.map(\.id))
        let transactionIDs = Set(transactions.map(\.id))
        let recurrenceIDs = Set(transactions.filter { contoID == nil || $0.type != .transfer }.map(\.id))
        var records: [SharedBookRecord] = []
        var assets: [SharedRecordID: Data] = [:]
        func id(_ kind: SharedRecordID.Kind, _ uuid: UUID) -> SharedRecordID {
            SharedRecordID(bookID: bookID, kind: kind, entityID: uuid.uuidString.lowercased())
        }
        func record(_ kind: SharedRecordID.Kind, _ uuid: UUID, _ fields: [String: SharedValue?]) -> SharedBookRecord {
            SharedBookRecord(id: id(kind, uuid), fields: fields.compactMapValues { $0 })
        }
        func reference(_ kind: SharedRecordID.Kind, _ uuid: UUID?) -> SharedValue? { uuid.map { .reference(id(kind, $0)) } }
        let bookReference = reference(.book, book.id)
        records.append(record(.book, book.id, ["name": book.name.map(SharedValue.text), "currency": book.currency.map(SharedValue.text),
            "externalID": .text(book.externalID), "createdAt": book.createdAt.map(SharedValue.date),
            "updatedAt": book.updatedAt.map(SharedValue.date), "isActive": book.isActive.map(SharedValue.flag),
            "budgetingPlan": book.budgetingPlanJSON.map(SharedValue.text)]))
        if let contoID, let conto = conti.first {
            records[0].fields = ["name": .text(conto.name ?? "Conto condiviso"),
                "currency": .text(book.currency ?? "EUR"), "externalID": .text(contoID.uuidString),
                "isActive": .flag(true), "shareKind": .text("conto"),
                "sharedConto": .reference(id(.conto, contoID))]
        }
        for conto in conti {
            records.append(record(.conto, conto.id, ["book": bookReference, "externalID": .text(conto.externalID),
                "name": conto.name.map(SharedValue.text), "type": conto.type.map { .text($0.rawValue) },
                "initialBalance": conto.initialBalance.map(SharedValue.decimal),
                "balanceVerifiedAt": conto.balanceVerifiedAt.map(SharedValue.date),
                "balanceVerificationFingerprint": conto.balanceVerificationFingerprint.map(SharedValue.text), "createdAt": conto.createdAt.map(SharedValue.date),
                "updatedAt": conto.updatedAt.map(SharedValue.date), "isActive": conto.isActive.map(SharedValue.flag),
                "description": conto.contoDescription.map(SharedValue.text), "color": conto.color.map(SharedValue.text),
                "logo": conto.logoData.map { .text($0.base64EncodedString()) },
                "creditLimit": conto.creditLimit.map(SharedValue.decimal), "statementClosingDay": conto.statementClosingDay.map(SharedValue.integer),
                "paymentDueDay": conto.paymentDueDay.map(SharedValue.integer), "annualInterestRate": conto.annualInterestRate.map(SharedValue.decimal),
                "savingsGoal": conto.savingsGoal.map(SharedValue.decimal),
                "savingsRates": conto.savingsRatesJSON.map(SharedValue.text),
                "linkedSavingsGoal": reference(.goal, conto.savingsGoalID.flatMap { goalID in (book.savingsGoals ?? []).contains { $0.id == goalID } ? goalID : nil })]))
        }
        if contoID != nil {
            for index in records.indices where records[index].id.kind == .conto {
                for key in ["externalID", "description", "linkedSavingsGoal", "balanceVerificationFingerprint"] { records[index].fields[key] = nil }
                records[index].fields["externalID"] = .text(records[index].id.entityID)
            }
        }
        for category in categories {
            if let parent = category.parentCategoryId, !sharedCategoryIDs.contains(parent) { throw Failure.invalidBoundary }
            records.append(record(.category, category.id, ["book": bookReference, "externalID": .text(category.externalID),
                "name": category.name.map(SharedValue.text), "color": category.color.map(SharedValue.text),
                "icon": category.icon.map(SharedValue.text), "createdAt": category.createdAt.map(SharedValue.date),
                "updatedAt": category.updatedAt.map(SharedValue.date), "isActive": category.isActive.map(SharedValue.flag),
                "kind": category.kindRaw.map(SharedValue.text),
                "parent": reference(.category, category.parentCategoryId.flatMap { sharedCategoryIDs.contains($0) ? $0 : nil })]))
        }
        for transaction in transactions {
            // A cross-book transfer keeps its type and amounts, but never exposes
            // the counterparty account or category outside the selected book.
            let from = transaction.type == .income ? nil : (transaction.fromContoId ?? transaction.fromConto?.id).flatMap { contoIDs.contains($0) ? $0 : nil }
            let to = transaction.type == .expense ? nil : (transaction.toContoId ?? transaction.toConto?.id).flatMap { contoIDs.contains($0) ? $0 : nil }
            let originalCategory = transaction.categoryId ?? transaction.category?.id
            if transaction.type != .transfer, let originalCategory, !sharedCategoryIDs.contains(originalCategory) { throw Failure.invalidBoundary }
            let category = originalCategory.flatMap { sharedCategoryIDs.contains($0) ? $0 : nil }
            records.append(record(.transaction, transaction.id, ["book": bookReference,
                "externalID": .text(transaction.externalID), "amount": transaction.amount.map(SharedValue.decimal),
                "destinationAmount": transaction.destinationAmount.map(SharedValue.decimal), "isSavingsInterest": transaction.isSavingsInterest.map(SharedValue.flag), "date": .date(transaction.date),
                "createdAt": transaction.createdAt.map(SharedValue.date), "updatedAt": transaction.updatedAt.map(SharedValue.date),
                "description": transaction.transactionDescription.map(SharedValue.text), "notes": transaction.notes.map(SharedValue.text),
                "createdBy": transaction.createdByJSON.map(SharedValue.text),
                "lastEditedBy": transaction.lastEditedByJSON.map(SharedValue.text),
                "assignedTo": transaction.assignedToJSON.map(SharedValue.text),
                "contributor": transaction.contributorJSON.map(SharedValue.text),
                "type": .text(transaction.typeRaw), "fromConto": reference(.conto, from), "toConto": reference(.conto, to),
                "category": reference(.category, category), "originalAmount": transaction.originalAmount.map(SharedValue.decimal),
                "originalCurrency": transaction.originalCurrency.map(SharedValue.text), "exchangeRate": transaction.exchangeRate.map(SharedValue.decimal),
                "exchangeRateDate": transaction.exchangeRateDate.map(SharedValue.text), "exchangeRateSource": transaction.exchangeRateSource.map(SharedValue.text),
                "placeName": transaction.placeName.map(SharedValue.text), "latitude": transaction.latitude.map(SharedValue.number),
                "longitude": transaction.longitude.map(SharedValue.number), "locationAccuracy": transaction.locationAccuracy.map(SharedValue.number),
                "isRecurring": transaction.isRecurring.map(SharedValue.flag), "recurrenceFrequency": transaction.recurrenceFrequency.map { .text($0.rawValue) },
                "recurrenceEndDate": transaction.recurrenceEndDate.map(SharedValue.date),
                "recurrenceSource": reference(.transaction, transaction.recurrenceSourceID.flatMap { transactionIDs.contains($0) ? $0 : nil })]))
            let privateTransfer = contoID != nil && transaction.type == .transfer && (from == nil || to == nil)
            if privateTransfer {
                let index = records.count - 1
                let amount = to != nil ? transaction.destinationAmount ?? transaction.amount : transaction.amount
                let kept = Set(["book", "amount", "date", "createdAt", "updatedAt", "type", "fromConto", "toConto", "createdBy", "lastEditedBy", "assignedTo", "contributor"])
                records[index].fields = records[index].fields.filter { kept.contains($0.key) }
                records[index].fields["amount"] = amount.map(SharedValue.decimal)
                records[index].fields["externalID"] = .text(transaction.id.uuidString.lowercased())
                records[index].fields["description"] = .text(to != nil ? "Versamento al conto condiviso" : "Trasferimento dal conto condiviso")
            }
            for attachment in privateTransfer ? [] : transaction.attachments ?? [] {
                guard let bytes = attachment.data else { throw Failure.missingAttachment }
                let assetID = id(.attachment, attachment.id)
                guard assets[assetID] == nil else { throw Failure.duplicateIdentity }
                assets[assetID] = bytes
                records.append(record(.attachment, attachment.id, ["transaction": reference(.transaction, transaction.id),
                    "filename": .text(attachment.filename), "contentType": .text(attachment.contentType), "createdAt": .date(attachment.createdAt),
                    "contentDigest": .text(SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined())]))
            }
        }
        for budget in contoID == nil ? book.budgets ?? [] : [] {
            guard (budget.categories ?? []).allSatisfy({ categoryIDs.contains($0.id) }) else { throw Failure.invalidBoundary }
            let refs = (budget.categories ?? []).filter { categoryIDs.contains($0.id) }.map { id(.category, $0.id) }.sorted { $0.recordName < $1.recordName }
            records.append(record(.budget, budget.id, ["book": bookReference, "externalID": .text(budget.externalID),
                "name": budget.name.map(SharedValue.text), "amount": budget.amount.map(SharedValue.decimal),
                "period": budget.period.map { .text($0.rawValue) }, "isActive": budget.isActive.map(SharedValue.flag),
                "createdAt": budget.createdAt.map(SharedValue.date), "updatedAt": budget.updatedAt.map(SharedValue.date),
                "threshold": budget.alertThreshold.map(SharedValue.number), "includeRecurring": budget.includeRecurringTransactions.map(SharedValue.flag),
                "categories": .references(refs), "exactCategories": budget.usesExactCategories.map(SharedValue.flag),
                "planningGroup": budget.planningGroupRaw.map(SharedValue.text)]))
        }
        for goal in contoID == nil ? book.savingsGoals ?? [] : [] {
            records.append(record(.goal, goal.id, ["book": bookReference, "externalID": .text(goal.externalID),
                "name": goal.name.map(SharedValue.text), "targetAmount": goal.targetAmount.map(SharedValue.decimal),
                "currentAmount": goal.currentAmount.map(SharedValue.decimal), "targetDate": goal.targetDate.map(SharedValue.date),
                "category": goal.category.map { .text($0.rawValue) }, "status": goal.status.map { .text($0.rawValue) },
                "createdAt": goal.createdAt.map(SharedValue.date), "updatedAt": goal.updatedAt.map(SharedValue.date),
                "description": goal.goalDescription.map(SharedValue.text), "isActive": goal.isActive.map(SharedValue.flag)]))
        }
        for resolution in try context.fetch(FetchDescriptor<RecurrenceResolution>()) where recurrenceIDs.contains(resolution.sourceID) {
            records.append(SharedBookRecord(id: SharedRecordID(bookID: bookID, kind: .recurrence, entityID: resolution.key), fields: [
                "source": .reference(id(.transaction, resolution.sourceID)), "scheduledDate": .date(resolution.scheduledDate),
                "transaction": reference(.transaction, resolution.transactionID.flatMap { transactionIDs.contains($0) ? $0 : nil }),
                "isSkipped": .flag(resolution.isSkipped), "createdAt": .date(resolution.createdAt)].compactMapValues { $0 }))
        }
        guard Set(records.map(\.id)).count == records.count else { throw Failure.duplicateIdentity }
        return SharedBookExport(bookID: bookID, records: records.sorted { $0.id.recordName < $1.id.recordName }, assets: assets)
    }
}
