import Darwin
import Foundation
import Testing
@testable import YabaiStacksCore

@Suite("Notification socket")
struct NotificationSocketTests {
    private func temporaryPath() -> String {
        NSTemporaryDirectory() + "yabai-stacks-test-\(UInt32.random(in: 0..<UInt32.max)).socket"
    }

    @Test("the default path is per-user and overridable")
    func defaultPath() {
        #expect(NotificationSocket.defaultPath(environment: ["USER": "anuj"])
            == NSTemporaryDirectory() + "yabai-stacks_anuj.socket")
        #expect(NotificationSocket.defaultPath(environment: [:])
            == NSTemporaryDirectory() + "yabai-stacks_unknown.socket")
        #expect(
            NotificationSocket.defaultPath(environment: ["YABAI_STACKS_SOCKET": "/tmp/custom.socket"])
                == "/tmp/custom.socket"
        )
        #expect(
            NotificationSocket.defaultPath(environment: ["YABAI_STACKS_SOCKET": "", "USER": "anuj"])
                == NSTemporaryDirectory() + "yabai-stacks_anuj.socket"
        )
    }

    /// The socket path is never the one yabai itself listens on; these tests
    /// bind their own under the temporary directory.
    @Test("test sockets never collide with yabai's own")
    func testPathsAreIsolated() {
        let path = temporaryPath()
        #expect(path.hasPrefix(NSTemporaryDirectory()))
        #expect(!path.contains("/yabai_"))
    }

    @Test("a notify wakes a listening socket")
    func notifyWakesListener() throws {
        let socket = NotificationSocket(path: temporaryPath())
        let received = EventLog()
        try socket.listen { received.append($0) }
        defer { socket.stop() }

        try NotificationSocket.notify(path: socket.path)
        #expect(received.waitForCount(atLeast: 1))
    }

    @Test("each notify is delivered separately")
    func repeatedNotifiesAreCounted() throws {
        let socket = NotificationSocket(path: temporaryPath())
        let received = EventLog()
        try socket.listen { received.append($0) }
        defer { socket.stop() }

        for _ in 0..<5 { try NotificationSocket.notify(path: socket.path) }
        #expect(received.waitForCount(atLeast: 5))
    }

    @Test("notifying a path nobody is listening on fails rather than hanging")
    func notifyWithoutListenerFails() {
        #expect(throws: YabaiError.self) {
            try NotificationSocket.notify(path: temporaryPath())
        }
    }

    /// An ungraceful exit leaves the socket file behind; binding must reclaim
    /// it rather than failing with EADDRINUSE for the rest of the login session.
    @Test("a stale socket file is reclaimed on listen")
    func staleSocketIsReclaimed() throws {
        let path = temporaryPath()
        let first = NotificationSocket(path: path)
        try first.listen { _ in }
        // Deliberately not calling stop(): this models a killed process.

        let second = NotificationSocket(path: path)
        let received = EventLog()
        try second.listen { received.append($0) }
        defer { second.stop() }

        try NotificationSocket.notify(path: path)
        #expect(received.waitForCount(atLeast: 1))
    }

    @Test("the event name survives a round trip")
    func eventNameRoundTrips() throws {
        let socket = NotificationSocket(path: temporaryPath())
        let received = EventLog()
        try socket.listen { received.append($0) }
        defer { socket.stop() }

        let events: [YabaiSignalEvent] = [.windowCreated, .missionControlEnter, .missionControlExit]
        for event in events { try NotificationSocket.notify(path: socket.path, event: event.rawValue) }

        #expect(received.waitForCount(atLeast: events.count))
        #expect(received.names.count == events.count)
        #expect(received.names.compactMap { $0 } == events.map(\.rawValue))
    }

    /// Accept order is the order yabai fired the events. A real `--notify` is a
    /// whole process launch between its `connect` and its `send`, so the peer
    /// accepted second can have its bytes ready first — and delivery must still
    /// follow accept order. Mission Control enter/exit is a toggle, so one
    /// inversion parks the strips off screen until the user opens Mission
    /// Control again; it is not a dropped frame that the next event repairs.
    @Test("delivery follows accept order even when the payloads do not")
    func deliveryFollowsAcceptOrder() throws {
        let socket = NotificationSocket(path: temporaryPath())
        let received = EventLog()
        try socket.listen { received.append($0) }
        defer { socket.stop() }

        let first = try RawClient.connect(to: socket.path)
        usleep(50_000)
        let second = try RawClient.connect(to: socket.path)
        usleep(50_000)

        // The later connection speaks first, and finishes first.
        RawClient.write("mission_control_exit", to: second)
        close(second)
        usleep(50_000)
        RawClient.write("mission_control_enter", to: first)
        close(first)

        #expect(received.waitForCount(atLeast: 2))
        #expect(received.names.compactMap { $0 } == ["mission_control_enter", "mission_control_exit"])
    }

    @Test("a burst of alternating events arrives in the order it was sent")
    func alternatingBurstKeepsItsOrder() throws {
        let socket = NotificationSocket(path: temporaryPath())
        let received = EventLog()
        try socket.listen { received.append($0) }
        defer { socket.stop() }

        let sent = (0..<16).map { $0.isMultiple(of: 2) ? "mission_control_enter" : "mission_control_exit" }
        for name in sent { try NotificationSocket.notify(path: socket.path, event: name) }

        #expect(received.waitForCount(atLeast: sent.count))
        #expect(received.names.compactMap { $0 } == sent)
    }

    /// bind() creates the node with the process umask; /tmp neighbours must not
    /// be able to connect and drive the daemon.
    @Test("the socket file is reachable only by its owner")
    func socketFileIsPrivate() throws {
        let socket = NotificationSocket(path: temporaryPath())
        try socket.listen { _ in }
        defer { socket.stop() }

        let attributes = try FileManager.default.attributesOfItem(atPath: socket.path)
        let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
        #expect(permissions.int16Value == 0o600)
    }

    /// The read deadline is the only thing stopping a silent peer from holding
    /// the serial read queue for ever, which would leave every event behind it
    /// undelivered.
    @Test("a silent peer is given up on within the read deadline")
    func silentPeerIsAbandonedOnDeadline() throws {
        let socket = NotificationSocket(path: temporaryPath())
        let received = EventLog()
        try socket.listen { received.append($0) }
        defer { socket.stop() }

        let silent = try RawClient.connect(to: socket.path)
        defer { close(silent) }

        #expect(NotificationSocket.readDeadline < 1)
        #expect(received.waitForCount(atLeast: 1, timeout: 1))
        #expect(received.names == [nil])
    }

    /// SOCK_STREAM has no framing, so a name can arrive in pieces. A partial
    /// "mission_control_ent" matches no event and would silently demote a hide
    /// to an ordinary refresh, leaving the strips over Mission Control.
    @Test("a name split across two writes is reassembled")
    func splitNameIsReassembled() throws {
        let socket = NotificationSocket(path: temporaryPath())
        let received = EventLog()
        try socket.listen { received.append($0) }
        defer { socket.stop() }

        let peer = try RawClient.connect(to: socket.path)
        RawClient.write("mission_control_ent", to: peer)
        usleep(30_000)
        RawClient.write("er", to: peer)
        close(peer)

        #expect(received.waitForCount(atLeast: 1))
        #expect(received.names == ["mission_control_enter"])
        #expect(received.names.compactMap { $0 }.compactMap(YabaiSignalEvent.init(rawValue:)) == [.missionControlEnter])
    }

    /// The daemon distinguishes "no event" from an event it does not know, so a
    /// wake-up carrying nothing has to arrive as nil rather than as "".
    @Test("a notify with no event delivers nil")
    func notifyWithoutEventIsNil() throws {
        let socket = NotificationSocket(path: temporaryPath())
        let received = EventLog()
        try socket.listen { received.append($0) }
        defer { socket.stop() }

        try NotificationSocket.notify(path: socket.path)
        try NotificationSocket.notify(path: socket.path, event: "")

        #expect(received.waitForCount(atLeast: 2))
        #expect(received.names.allSatisfy { $0 == nil })
    }

    /// The listener reads into a fixed 64-byte buffer and decodes leniently, so
    /// a payload that is too long or not UTF-8 has to truncate rather than trap.
    @Test("an oversized or malformed payload is survivable")
    func garbagePayloadIsSurvivable() throws {
        let socket = NotificationSocket(path: temporaryPath())
        let received = EventLog()
        try socket.listen { received.append($0) }
        defer { socket.stop() }

        try RawClient.send([UInt8](repeating: 0x41, count: 16 * 1024), to: socket.path)
        try RawClient.send([0xff, 0xfe, 0xc3], to: socket.path)
        #expect(received.waitForCount(atLeast: 2))
        #expect(received.names.compactMap { $0 }.allSatisfy { YabaiSignalEvent(rawValue: $0) == nil })

        // The socket is still usable afterwards, which is the point.
        try NotificationSocket.notify(path: socket.path, event: "space_changed")
        #expect(received.waitForName("space_changed"))
    }

    /// The wedge: reading on the accept thread meant one peer that connected
    /// and then said nothing blocked every later wake-up behind it, leaving the
    /// daemon deaf at 0% CPU with no error anywhere.
    @Test("a silent peer does not stall the next notify")
    func silentPeerDoesNotStallDelivery() throws {
        let socket = NotificationSocket(path: temporaryPath())
        let received = EventLog()
        try socket.listen { received.append($0) }
        defer { socket.stop() }

        let silent = try RawClient.connect(to: socket.path)
        defer { close(silent) }

        try NotificationSocket.notify(path: socket.path, event: "window_focused")
        #expect(received.waitForName("window_focused", timeout: 5))
    }

    @Test("stopping removes the socket file")
    func stopUnlinks() throws {
        let socket = NotificationSocket(path: temporaryPath())
        try socket.listen { _ in }
        #expect(FileManager.default.fileExists(atPath: socket.path))

        socket.stop()
        #expect(!FileManager.default.fileExists(atPath: socket.path))
    }
}

private final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String?] = []

    func append(_ name: String?) {
        lock.lock()
        values.append(name)
        lock.unlock()
    }

    var names: [String?] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }

    func waitForCount(atLeast target: Int, timeout: TimeInterval = 10) -> Bool {
        wait(timeout: timeout) { $0.count >= target }
    }

    func waitForName(_ name: String, timeout: TimeInterval = 10) -> Bool {
        wait(timeout: timeout) { $0.contains(name) }
    }

    // The predicate is re-checked once the deadline passes: a machine that
    // descheduled this thread for the whole budget has not proved anything.
    private func wait(timeout: TimeInterval, until: ([String?]) -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if until(names) { return true }
            usleep(2000)
        }
        return until(names)
    }
}

/// Speaks the wake-up protocol directly, so a test can send bytes `notify`
/// would never produce, or connect and deliberately say nothing.
private enum RawClient {
    enum Failure: Error { case connect(Int32) }

    static func connect(to path: String) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure.connect(errno) }

        // Without these a write to a peer that has already read its 64 bytes
        // and closed would kill the test process with SIGPIPE, or block for
        // ever once the socket buffers fill.
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<Darwin.timeval>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, size) }
        }
        guard result == 0 else {
            let code = errno
            close(fd)
            throw Failure.connect(code)
        }
        return fd
    }

    static func send(_ bytes: [UInt8], to path: String) throws {
        let fd = try connect(to: path)
        defer { close(fd) }
        write(bytes, to: fd)
    }

    static func write(_ text: String, to fd: Int32) {
        write(Array(text.utf8), to: fd)
    }

    static func write(_ bytes: [UInt8], to fd: Int32) {
        _ = bytes.withUnsafeBytes { Darwin.send(fd, $0.baseAddress, $0.count, 0) }
    }
}
