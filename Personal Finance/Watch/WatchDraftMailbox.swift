import Foundation

/// The reply acknowledges a durable draft, never a saved financial movement.
@MainActor
final class WatchDraftMailbox {
    static let shared = WatchDraftMailbox(defaults: .standard)
    private struct State: Codable {
        var pending: WatchExpenseDraft?
        var deliveredIDs: [UUID] = []
    }
    private let defaults: UserDefaults
    private let key = "forgia.watch.draftMailbox.v1"
    private var state: State
    private var presentedID: UUID?
    var pending: WatchExpenseDraft? { state.pending }
    var awaitingPresentation: WatchExpenseDraft? { presentedID == state.pending?.id ? nil : state.pending }
    func presented(_ id: UUID) {
        guard state.pending?.id == id else { return }
        presentedID = id
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        state = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(State.self, from: $0) } ?? State()
    }
    func receive(_ draft: WatchExpenseDraft) -> WatchReply.Status {
        guard draft.normalizedAmount != nil else { return .invalid }
        if state.deliveredIDs.contains(draft.id) || state.pending == draft { return .accepted }
        guard state.pending == nil else { return .busy }
        state.pending = draft
        persist()
        return .accepted
    }
    func delivered(_ id: UUID) {
        guard state.pending?.id == id else { return }
        state.pending = nil
        presentedID = nil
        state.deliveredIDs.append(id)
        state.deliveredIDs = Array(state.deliveredIDs.suffix(100))
        persist()
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: key) }
    }
}
