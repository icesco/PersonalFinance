import Foundation
import CryptoKit

/// Reconciles three complete snapshots. Network pages must be accumulated first.
public enum SharedBookReconciliation {
    public enum Failure: Error { case invalidSnapshot, incompleteRemote, missingAsset }
    public struct Plan: Sendable {
        public let records: [SharedBookRecord]
        public let assets: [SharedRecordID: Data]
        public let uploads: [SharedBookRecord]
        public let conflicts: [SharedBookConflict]
        /// A deletion can conflict with a newly created child even if no individual
        /// record has competing edits. Never apply that incomplete graph.
        public let unresolvedReferences: Set<SharedRecordID>
        public var canApply: Bool { conflicts.isEmpty && unresolvedReferences.isEmpty }
    }

    public static func reconcile(bookID: UUID, base: [SharedBookRecord], local: [SharedBookRecord], remote: [SharedBookRecord],
                                 localAssets: [SharedRecordID: Data], remoteAssets: [SharedRecordID: Data],
                                 decisions: [SharedBookDecision] = []) throws -> Plan {
        guard Set(decisions.map { $0.expected.local.id }).count == decisions.count else { throw Failure.invalidSnapshot }
        let choices = Dictionary(uniqueKeysWithValues: decisions.map { ($0.expected.local.id, $0) })
        func index(_ records: [SharedBookRecord]) throws -> [SharedRecordID: SharedBookRecord] {
            var result: [SharedRecordID: SharedBookRecord] = [:]
            for record in records {
                guard record.version == 1, record.id.bookID == bookID, result[record.id] == nil,
                      !record.deleted || record.fields.isEmpty else { throw Failure.invalidSnapshot }
                result[record.id] = record
            }
            return result
        }
        let old = try index(base), lhs = try index(local), rhs = try index(remote)
        func referenceNames(_ record: SharedBookRecord, preferred: [SharedRecordID: SharedBookRecord], fallback: [SharedRecordID: SharedBookRecord]) -> [SharedRecordID: String] {
            var names: [SharedRecordID: String] = [:]
            for value in record.fields.values {
                let references: [SharedRecordID]
                switch value {
                case let .reference(id): references = [id]
                case let .references(ids): references = ids
                default: references = []
                }
                for id in references {
                    guard let referenced = preferred[id] ?? fallback[id] else { continue }
                    for key in ["name", "description", "filename"] {
                        if case let .text(name)? = referenced.fields[key], !name.isEmpty { names[id] = name; break }
                    }
                    if names[id] == nil, case let .date(date)? = referenced.fields["date"] {
                        names[id] = date.formatted(date: .abbreviated, time: .omitted)
                    }
                }
            }
            return names
        }
        // Tombstones are retained on the server. A disappeared acknowledged
        // record is a reset/incomplete download, not permission to recreate it.
        guard old.keys.allSatisfy({ rhs[$0] != nil }) else { throw Failure.incompleteRemote }
        var merged: [SharedRecordID: SharedBookRecord] = [:]
        var conflicts: [SharedBookConflict] = []
        for id in Set(old.keys).union(lhs.keys).union(rhs.keys).sorted(by: { $0.recordName < $1.recordName }) {
            let localRecord = lhs[id] ?? old[id]?.tombstone()
            switch (localRecord, rhs[id]) {
            case let (local?, remote?):
                switch try SharedBookMerge.merge(base: old[id], local: local, remote: remote) {
                case let .merged(record): merged[id] = record
                case .conflict(var conflict):
                    conflict.localReferenceNames = referenceNames(local, preferred: lhs, fallback: rhs)
                    conflict.remoteReferenceNames = referenceNames(remote, preferred: rhs, fallback: lhs)
                    if let choice = choices[id], choice.expected == conflict {
                        merged[id] = try choice.resolved()
                    } else { conflicts.append(conflict) }
                }
            case let (local?, nil): merged[id] = local
            case let (nil, remote?): merged[id] = remote
            case (nil, nil): break
            }
        }
        var unresolved: Set<SharedRecordID> = []
        let rootID = SharedRecordID(bookID: bookID, kind: .book, entityID: bookID.uuidString.lowercased())
        let disputed = Set(conflicts.map { $0.local.id })
        if merged[rootID] == nil && !disputed.contains(rootID) { unresolved.insert(rootID) }
        for record in merged.values where !record.deleted {
            if record.id != rootID && merged[rootID]?.deleted == true { unresolved.insert(rootID) }
            for value in record.fields.values {
                let references: [SharedRecordID]
                switch value {
                case let .reference(id): references = [id]
                case let .references(ids): references = ids
                default: references = []
                }
                for id in references where merged[id]?.deleted != false && !disputed.contains(id) { unresolved.insert(id) }
            }
        }
        var assets: [SharedRecordID: Data] = [:]
        for record in merged.values where record.id.kind == .attachment && !record.deleted {
            guard case let .text(expected)? = record.fields["contentDigest"] else { throw Failure.missingAsset }
            let candidates = [remoteAssets[record.id], localAssets[record.id]].compactMap { $0 }
            guard let bytes = candidates.first(where: { data in
                data.count <= 10 * 1024 * 1024 && SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == expected
            }) else { throw Failure.missingAsset }
            assets[record.id] = bytes
        }
        let records = merged.values.sorted { $0.id.recordName < $1.id.recordName }
        // Expose no upload work until the complete graph is reconciled.
        let uploads = conflicts.isEmpty && unresolved.isEmpty ? records.filter { rhs[$0.id] != $0 } : []
        return Plan(records: records, assets: assets, uploads: uploads, conflicts: conflicts, unresolvedReferences: unresolved)
    }
}
