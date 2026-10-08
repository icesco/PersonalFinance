#if os(macOS)
import AppKit
import FinanceCore
import Testing
@testable import Personal_Finance

@MainActor
struct FormiCLIReceiverTests {
    @Test func burstIsBoundedSerializedAndDeduplicatedWithoutOpeningWindows() async throws {
        let ids = (0...FormiCLIReceiver.maximumPendingRequests).map { _ in UUID() }
        defer {
            for id in ids { NSPasteboard(name: .init(FormiCLIWire.pasteboardName(id))).releaseGlobally() }
        }
        let windows = NSApp.windows.map(\.windowNumber)
        let started = AsyncStream<Void>.makeStream()
        let finished = AsyncStream<Void>.makeStream()
        var release: CheckedContinuation<Void, Never>?
        var processed: [UUID] = []
        let receiver = FormiCLIReceiver(name: "formi.tests.\(UUID())") { id in
            processed.append(id)
            if processed.count == 1 {
                await withCheckedContinuation { continuation in
                    release = continuation
                    started.continuation.yield(())
                }
            }
            if processed.count == FormiCLIReceiver.maximumPendingRequests {
                finished.continuation.yield(())
            }
        }
        receiver.enqueue(ids[0])
        var start = started.stream.makeAsyncIterator()
        _ = await start.next()
        receiver.enqueue(ids[0])
        for id in ids.dropFirst() { receiver.enqueue(id) }
        #expect(processed == [ids[0]])
        let overflow = NSPasteboard(name: .init(FormiCLIWire.pasteboardName(ids.last!)))
        let data = try #require(overflow.data(forType: .init(FormiCLIWire.responseType)))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((json["error"] as? [String: String])?["code"] == "app_busy")
        release?.resume()
        var finish = finished.stream.makeAsyncIterator()
        _ = await finish.next()
        #expect(processed == Array(ids.prefix(FormiCLIReceiver.maximumPendingRequests)))
        #expect(NSApp.windows.map(\.windowNumber) == windows)
        started.continuation.finish()
        finished.continuation.finish()
    }

    @Test func distributedDeliveryUsesOneReceiverAndDoesNotOpenWindows() async {
        let name = "formi.tests.\(UUID())"
        let id = UUID()
        defer { NSPasteboard(name: .init(FormiCLIWire.pasteboardName(id))).releaseGlobally() }
        let windows = NSApp.windows.map(\.windowNumber)
        let received = AsyncStream<UUID>.makeStream()
        let receiver = FormiCLIReceiver(name: name) { received.continuation.yield($0) }
        DistributedNotificationCenter.default().postNotificationName(.init(name), object: id.uuidString,
            userInfo: nil, deliverImmediately: true)
        var iterator = received.stream.makeAsyncIterator()
        #expect(await iterator.next() == id)
        #expect(NSApp.windows.map(\.windowNumber) == windows)
        withExtendedLifetime(receiver) {}
        received.continuation.finish()
    }

    @Test func notificationRoutesAreSeparateForEachCopyAndConfiguration() {
        let release = FormiCLIWire.requestNotificationName(appPath: "/Applications/Formi.app", configuration: "release")
        #expect(release != FormiCLIWire.requestNotificationName(appPath: "/tmp/Formi.app", configuration: "release"))
        #expect(release != FormiCLIWire.requestNotificationName(appPath: "/Applications/Formi.app", configuration: "debug"))
    }
}
#endif
