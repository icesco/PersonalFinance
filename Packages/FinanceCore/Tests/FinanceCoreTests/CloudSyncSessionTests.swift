import Foundation
import Testing
@testable import FinanceCore

struct CloudSyncSessionTests {
    private func time(_ seconds: Double) -> Date { Date(timeIntervalSince1970: seconds) }

    @Test(arguments: [false, true])
    func trackedLateFailureIsDeliveredWithoutReopeningProgress(overlapping: Bool) {
        struct Failure: Error {}
        var progress = CloudSyncProgress()
        var session = CloudSyncSession()
        let event = UUID()
        progress.begin(event)
        if overlapping { progress.begin(UUID()) }
        session.activity(at: time(0), hasActiveEvents: progress.isSyncing)
        #expect(session.advance(to: time(3)) == .announce)
        #expect(session.advance(to: time(20)) == .stale)
        #expect(progress.isTracking(event))
        #expect(!session.isActive)

        progress.finish(event, at: time(25), isDataSync: true, error: Failure())
        let step = session.activity(at: time(25), hasActiveEvents: progress.isSyncing, failed: true)
        #expect(step == .failed)
        #expect(!session.isActive)
        #expect(session.nextDeadline == nil)
        #expect(session.advance(to: time(30)) == .none)
        #expect(!progress.isTracking(event)) // Helper ignores duplicate completions before calling activity.
        #expect(progress.lastSyncDate == nil)

        if !overlapping {
            let retry = UUID()
            progress.begin(retry)
            #expect(session.activity(at: time(31), hasActiveEvents: progress.isSyncing) == .none)
            progress.finish(retry, at: time(31.1), isDataSync: true, error: nil)
            session.activity(at: time(31.1), hasActiveEvents: progress.isSyncing)
            #expect(session.advance(to: time(33.1)) == .completed)
            #expect(progress.lastSyncDate == time(31.1))
        }
    }

    @Test func lateSuccessRemainsQuietAndUpdatesRecordedSyncDate() {
        var progress = CloudSyncProgress()
        var session = CloudSyncSession()
        let event = UUID()
        progress.begin(event)
        session.activity(at: time(0), hasActiveEvents: true)
        #expect(session.advance(to: time(20)) == .stale)
        progress.finish(event, at: time(25), isDataSync: true, error: nil)
        #expect(session.activity(at: time(25), hasActiveEvents: progress.isSyncing) == .none)
        #expect(session.nextDeadline == nil)
        #expect(!session.isActive)
        #expect(progress.lastSyncDate == time(25))
    }

    @Test func knownFailureSurvivesTimeoutOfAnotherActiveEvent() {
        var session = CloudSyncSession()
        session.activity(at: time(0), hasActiveEvents: true)
        #expect(session.activity(at: time(1), hasActiveEvents: true, failed: true) == .none)
        #expect(session.advance(to: time(3)) == .announce)
        #expect(session.advance(to: time(21)) == .failed)
        #expect(!session.isActive)
        #expect(session.advance(to: time(25)) == .none)
    }

    @Test func fastSyncFinishesWithoutAnAnnouncement() {
        var session = CloudSyncSession()
        session.activity(at: time(0), hasActiveEvents: true)
        session.activity(at: time(0.1), hasActiveEvents: false)
        #expect(session.nextDeadline == time(2.1))
        #expect(session.advance(to: time(2)) == .none)
        #expect(session.advance(to: time(2.1)) == .completed)
        #expect(!session.isActive)
        #expect(session.nextDeadline == nil)
        #expect(session.advance(to: time(10)) == .none)
    }

    @Test func separatedWavesAreOneSessionAndDoNotRestartSlowThreshold() {
        var session = CloudSyncSession()
        session.activity(at: time(0), hasActiveEvents: true)
        session.activity(at: time(0.2), hasActiveEvents: false)
        session.activity(at: time(1.9), hasActiveEvents: true)
        session.activity(at: time(2.1), hasActiveEvents: false)
        #expect(session.nextDeadline == time(3))
        #expect(session.advance(to: time(3)) == .announce)
        #expect(session.advance(to: time(3.2)) == .none)
        session.activity(at: time(4), hasActiveEvents: true)
        session.activity(at: time(4.3), hasActiveEvents: false)
        #expect(session.advance(to: time(5)) == .none)
        #expect(session.advance(to: time(6.3)) == .completed)
    }

    @Test func activeImportStaysVisibleAndSilenceNeverClaimsSuccess() {
        var session = CloudSyncSession()
        session.activity(at: time(0), hasActiveEvents: true)
        #expect(session.advance(to: time(3)) == .announce)
        #expect(session.advance(to: time(10)) == .none)
        session.activity(at: time(19), hasActiveEvents: true)
        #expect(session.advance(to: time(20)) == .none)
        #expect(session.advance(to: time(39)) == .stale)
        #expect(!session.isActive)
        session.activity(at: time(40), hasActiveEvents: false)
        #expect(!session.isActive)
        #expect(session.advance(to: time(50)) == .none)
    }

    @Test func failuresPersistAcrossWavesUntilQuietEndAndNextSessionCanRecover() {
        var session = CloudSyncSession()
        session.activity(at: time(0), hasActiveEvents: true)
        session.activity(at: time(0.5), hasActiveEvents: false, failed: true)
        session.activity(at: time(1), hasActiveEvents: true)
        session.activity(at: time(1.5), hasActiveEvents: false)
        #expect(session.advance(to: time(3)) == .announce)
        #expect(session.advance(to: time(3.5)) == .failed)
        session.activity(at: time(4), hasActiveEvents: true)
        session.activity(at: time(4.1), hasActiveEvents: false)
        #expect(session.advance(to: time(6.1)) == .completed)
    }

    @Test func resetCannotAnnounceAnOldContainerAndOverlapsDoNotFinishEarly() {
        var session = CloudSyncSession()
        session.activity(at: time(0), hasActiveEvents: true)
        session.activity(at: time(1), hasActiveEvents: true) // one of the two imports ended
        #expect(session.advance(to: time(3)) == .announce)
        #expect(session.advance(to: time(5)) == .none)
        session = CloudSyncSession()
        #expect(session.advance(to: time(30)) == .none)
        session.activity(at: time(31), hasActiveEvents: false)
        #expect(!session.isActive)
    }

    @Test func manyShortWavesProduceOneAnnouncementAndOneCompletion() {
        var session = CloudSyncSession()
        var announcements = 0, completions = 0
        for i in 0..<100 {
            let start = Double(i)
            session.activity(at: time(start), hasActiveEvents: true)
            if session.advance(to: time(start)) == .announce { announcements += 1 }
            session.activity(at: time(start + 0.1), hasActiveEvents: false)
            if session.advance(to: time(start + 0.1)) == .completed { completions += 1 }
        }
        if session.advance(to: time(102)) == .completed { completions += 1 }
        #expect(announcements == 1)
        #expect(completions == 1)
    }
}
