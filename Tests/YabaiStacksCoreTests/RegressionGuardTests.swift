import Foundation
import Testing
@testable import YabaiStacksCore

/// Cases a final review found were not pinned: each one here corresponds to a
/// mutation that previously left the whole suite green.
@Suite("Regression guards")
struct RegressionGuardTests {
    private let displays = [YabaiDisplay(index: 1, uuid: "D1", frame: YabaiFrame(x: 0, y: 0, w: 1800, h: 1169))]
    private let configuration = Configuration(titlebarInset: 0)

    private func stack(space: Int, frame: YabaiFrame, ids: [Int]) -> Stack {
        let members = ids.enumerated().map { index, id in
            Synthetic.window(id: id, space: space, stackIndex: index + 1, frame: frame)
        }
        return Stack(space: space, display: 1, frame: frame, members: members, activeWindowID: nil)
    }

    private func renders(_ stacks: [Stack]) -> [StripRender] {
        StripReconciler.renders(for: stacks, displays: displays, configuration: configuration)
    }

    /// Both new stacks carry the same member list, so both fall through to the
    /// member-match pass and target the one surviving panel. The second must be
    /// created, not handed a panel the first already claimed.
    @Test("one panel cannot be claimed by two rekeyed stacks")
    func onePanelCannotBeClaimedTwice() {
        let original = stack(space: 2, frame: Synthetic.leftLeaf, ids: [1, 2])
        let previous = Dictionary(renders([original]).map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })

        let movedA = stack(space: 2, frame: YabaiFrame(x: 10, y: 50, w: 400, h: 900), ids: [1, 2])
        let movedB = stack(space: 2, frame: YabaiFrame(x: 905, y: 50, w: 400, h: 900), ids: [1, 2])
        let diff = StripReconciler.reconcile(
            previous: previous,
            stacks: [movedA, movedB],
            displays: displays,
            configuration: configuration
        )

        #expect(diff.updated.count == 1)
        #expect(diff.created.count == 1)
        #expect(diff.removed.isEmpty)

        // Every live strip has its own panel: one reused, one new.
        let claimed = diff.updated.map(\.key) + diff.created.map(\.key)
        #expect(Set(claimed).count == 2)
    }

    /// A stack matched by key is recorded before one matched by member list, so
    /// without the final sort the diff reports them in match order rather than
    /// in the order the caller supplied.
    @Test("updates are reported in incoming stack order, not match order")
    func updatesKeepIncomingOrder() {
        let frames = (0..<4).map { YabaiFrame(x: 10, y: Double($0) * 200, w: 400, h: 150) }
        let before = frames.enumerated().map { index, frame in
            stack(space: index + 1, frame: frame, ids: [index * 10, index * 10 + 1])
        }
        let previous = Dictionary(renders(before).map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })

        // The first stack is resized, so it is matched by member list and lands
        // in the updates list last; the rest still match by key.
        var after = frames.enumerated().map { index, frame in
            stack(space: index + 1, frame: frame, ids: [index * 10, index * 10 + 1, index * 10 + 2])
        }
        after[0] = stack(space: 1, frame: YabaiFrame(x: 10, y: 0, w: 999, h: 150), ids: [0, 1])

        let diff = StripReconciler.reconcile(
            previous: previous,
            stacks: after,
            displays: displays,
            configuration: configuration
        )

        #expect(diff.updated.count == 4)
        #expect(diff.updated.map(\.key) == after.map(\.key))
        #expect(diff.updated.first?.isRekeyed == true)
    }

    @Test("a stopped socket stops delivering and can be stopped twice")
    func stoppedSocketIsInert() throws {
        let path = NSTemporaryDirectory() + "yabai-stacks-inert-\(UInt32.random(in: 0..<UInt32.max)).socket"
        let socket = NotificationSocket(path: path)
        let counter = Counter()
        try socket.listen { counter.increment() }

        try NotificationSocket.notify(path: path)
        #expect(counter.waitForCount(atLeast: 1))
        let delivered = counter.count

        socket.stop()
        // Idempotent: the daemon's SIGTERM handler and its atexit hook both run.
        socket.stop()

        #expect(!NotificationSocket.isServed(path: path))
        #expect(throws: YabaiError.self) { try NotificationSocket.notify(path: path) }
        #expect(counter.count == delivered)
    }

    @Test("isServed distinguishes a live socket from a stale file")
    func isServedDetectsLiveDaemonOnly() throws {
        let path = NSTemporaryDirectory() + "yabai-stacks-served-\(UInt32.random(in: 0..<UInt32.max)).socket"
        #expect(!NotificationSocket.isServed(path: path))

        let socket = NotificationSocket(path: path)
        try socket.listen {}
        #expect(NotificationSocket.isServed(path: path))

        socket.stop()
        #expect(!NotificationSocket.isServed(path: path))
    }

    /// NUL is the argv delimiter, so an element carrying one would arrive as
    /// several and defeat an audit that reads argv as `[String]`.
    @Test("a NUL in an argument is refused before it reaches the wire")
    func nulIsRefused() {
        #expect(YabaiWireFormat.containsDelimiter(["signal", "--add", "event=a\u{0}--extra"]))
        #expect(!YabaiWireFormat.containsDelimiter(["signal", "--add", "event=a"]))

        let transport = YabaiSocketTransport(path: NSTemporaryDirectory() + "never-opened.socket")
        #expect(throws: YabaiError.argumentContainsDelimiter) {
            _ = try transport.send(
                .addSignal(event: .windowCreated, notifying: "/bin/x\u{0}--notify", socket: "/tmp/s")
            )
        }
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func waitForCount(atLeast target: Int, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if count >= target { return true }
            usleep(2000)
        }
        return false
    }
}
