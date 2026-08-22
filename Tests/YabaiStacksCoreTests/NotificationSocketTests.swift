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
        let received = Counter()
        try socket.listen { received.increment() }
        defer { socket.stop() }

        try NotificationSocket.notify(path: socket.path)
        #expect(received.waitForCount(atLeast: 1))
    }

    @Test("each notify is delivered separately")
    func repeatedNotifiesAreCounted() throws {
        let socket = NotificationSocket(path: temporaryPath())
        let received = Counter()
        try socket.listen { received.increment() }
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
        try first.listen {}
        // Deliberately not calling stop(): this models a killed process.

        let second = NotificationSocket(path: path)
        let received = Counter()
        try second.listen { received.increment() }
        defer { second.stop() }

        try NotificationSocket.notify(path: path)
        #expect(received.waitForCount(atLeast: 1))
    }

    @Test("stopping removes the socket file")
    func stopUnlinks() throws {
        let socket = NotificationSocket(path: temporaryPath())
        try socket.listen {}
        #expect(FileManager.default.fileExists(atPath: socket.path))

        socket.stop()
        #expect(!FileManager.default.fileExists(atPath: socket.path))
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
