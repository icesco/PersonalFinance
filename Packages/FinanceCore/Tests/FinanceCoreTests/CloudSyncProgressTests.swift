import Foundation
import Testing
@testable import FinanceCore

struct CloudSyncProgressTests {
    private enum Failure: Error { case offline }

    @Test func overlappingImportAndExportFinishOnlyTogether() {
        var progress = CloudSyncProgress()
        let importing = UUID(), exporting = UUID()
        let transition10 = progress.begin(importing)
        #expect(transition10)
        let transition11 = !progress.begin(exporting)
        #expect(transition11)
        let transition12 = !progress.begin(importing)
        #expect(transition12)
        let transition13 = !progress.finish(importing, at: Date(timeIntervalSince1970: 20), isDataSync: true, error: nil)
        #expect(transition13)
        #expect(progress.isSyncing)
        #expect(progress.lastSyncDate == nil)
        let transition16 = progress.finish(exporting, at: Date(timeIntervalSince1970: 30), isDataSync: true, error: nil)
        #expect(transition16)
        #expect(!progress.isSyncing)
        #expect(progress.lastSyncDate == Date(timeIntervalSince1970: 30))
    }

    @Test func siblingSuccessDoesNotEraseFailure() {
        var progress = CloudSyncProgress()
        let importing = UUID(), exporting = UUID()
        progress.begin(importing)
        progress.begin(exporting)
        progress.finish(importing, at: .now, isDataSync: true, error: Failure.offline)
        progress.finish(exporting, at: .now, isDataSync: true, error: nil)
        #expect(progress.error != nil)
        #expect(progress.lastSyncDate == nil)
        let retry = UUID()
        progress.begin(retry)
        #expect(progress.error == nil)
        progress.finish(retry, at: Date(timeIntervalSince1970: 50), isDataSync: true, error: nil)
        #expect(progress.lastSyncDate == Date(timeIntervalSince1970: 50))
    }

    @Test func setupDoesNotClaimDataWasSynchronized() {
        var progress = CloudSyncProgress()
        let setup = UUID()
        progress.begin(setup)
        let transition41 = progress.finish(setup, at: .now, isDataSync: false, error: nil)
        #expect(transition41)
        #expect(progress.lastSyncDate == nil)
    }

    @Test func staleAndDuplicateCompletionsCannotEndAnotherOperation() {
        var progress = CloudSyncProgress()
        let old = UUID(), current = UUID()
        progress.begin(old)
        progress = CloudSyncProgress()
        progress.begin(current)
        let transition51 = !progress.finish(old, at: .now, isDataSync: true, error: nil)
        #expect(transition51)
        #expect(progress.isSyncing)
        #expect(progress.lastSyncDate == nil)
        let transition54 = progress.finish(current, at: Date(timeIntervalSince1970: 10), isDataSync: true, error: nil)
        #expect(transition54)
        let transition55 = !progress.finish(current, at: .now, isDataSync: true, error: Failure.offline)
        #expect(transition55)
        #expect(progress.error == nil)
        #expect(progress.lastSyncDate == Date(timeIntervalSince1970: 10))
    }
}
