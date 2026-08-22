import Darwin
import Foundation
import Testing
@testable import YabaiStacksCore

@Suite("YabaiSocketTransport against a locally bound socket", .serialized)
struct SocketTransportTests {
    @Test("test sockets live in the temporary directory, never at the yabai path")
    func neverTouchesTheRealSocket() throws {
        let server = try UnixSocketServer { _ in }
        defer { server.shutdown() }

        #expect(server.path.hasPrefix(NSTemporaryDirectory()))
        #expect(!server.path.hasPrefix("/tmp/yabai_"))
        #expect(server.path != YabaiSocketTransport.defaultPath())
    }

    @Test("round trip writes the exact frame and returns the payload")
    func roundTrip() throws {
        let payload = Data(#"[{"index":1}]"#.utf8)
        let server = try UnixSocketServer { descriptor in
            _ = UnixSocketServer.write(payload, to: descriptor)
        }
        defer { server.shutdown() }

        let transport = YabaiSocketTransport(path: server.path, timeout: 5)
        #expect(try transport.send(.query(.windows(.space(2)))) == payload)

        let expected = Data([0x1b, 0x00, 0x00, 0x00])
            + Data("query\u{0}--windows\u{0}--space\u{0}2\u{0}\u{0}".utf8)
        #expect(server.requests == [expected])
    }

    @Test("focus and query frames both arrive intact")
    func framesForBothCommands() throws {
        let server = try UnixSocketServer { _ in }
        defer { server.shutdown() }

        let transport = YabaiSocketTransport(path: server.path, timeout: 5)
        _ = try transport.send(.focusWindow(id: 577003))
        _ = try transport.send(.query(.displays))

        #expect(server.requests == [
            Data([0x17, 0x00, 0x00, 0x00]) + Data("window\u{0}--focus\u{0}577003\u{0}\u{0}".utf8),
            Data([0x12, 0x00, 0x00, 0x00]) + Data("query\u{0}--displays\u{0}\u{0}".utf8),
        ])
    }

    @Test("a response larger than the read buffer is reassembled across recv calls")
    func multiChunkResponse() throws {
        let payload = Data((0..<300_000).map { UInt8($0 % 251) })
        let server = try UnixSocketServer { descriptor in
            _ = UnixSocketServer.write(payload, to: descriptor)
        }
        defer { server.shutdown() }

        let transport = YabaiSocketTransport(path: server.path, timeout: 10)
        let response = try transport.send(.query(.windows(.all)))

        #expect(response.count == 300_000)
        #expect(response == payload)
    }

    @Test("a 0x07 response surfaces as remoteFailure")
    func remoteFailure() throws {
        let message = "could not locate window with the specified id '999999999'."
        let server = try UnixSocketServer { descriptor in
            _ = UnixSocketServer.write(Data([0x07]) + Data((message + "\n").utf8), to: descriptor)
        }
        defer { server.shutdown() }

        let transport = YabaiSocketTransport(path: server.path, timeout: 5)
        #expect(throws: YabaiError.remoteFailure(message)) {
            _ = try transport.send(.focusWindow(id: 999_999_999))
        }
    }

    @Test("a missing socket surfaces as connectionFailed with ENOENT")
    func connectionFailure() throws {
        let path = NSTemporaryDirectory() + "ys-absent-\(UUID().uuidString.prefix(8)).sock"
        let transport = YabaiSocketTransport(path: path, timeout: 1)

        let error = try #require(throws: YabaiError.self) { _ = try transport.send(.query(.displays)) }
        guard case .connectionFailed(let reported, let code) = error else {
            Issue.record("expected connectionFailed, got \(error)")
            return
        }
        #expect(reported == path)
        #expect(code == ENOENT)
    }

    @Test("a dribbling server is cut off by the whole-request deadline")
    func deadlineIsNotAnIdleTimer() throws {
        // 40 chunks, 0.1s apart: no single gap exceeds the 0.5s timeout, so
        // only an absolute deadline can stop this.
        let server = try UnixSocketServer { descriptor in
            for _ in 0..<40 {
                guard UnixSocketServer.write(Data([0x20]), to: descriptor) else { return }
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
        defer { server.shutdown() }

        let transport = YabaiSocketTransport(path: server.path, timeout: 0.5)
        let start = Date()
        #expect(throws: YabaiError.timedOut) { _ = try transport.send(.query(.displays)) }
        let elapsed = Date().timeIntervalSince(start)

        #expect(elapsed >= 0.4)
        #expect(elapsed < 2, "deadline did not fire; took \(elapsed)s")
    }

    @Test("an oversized response is refused")
    func responseCap() throws {
        let server = try UnixSocketServer { descriptor in
            _ = UnixSocketServer.write(Data(repeating: 0x41, count: 400_000), to: descriptor)
        }
        defer { server.shutdown() }

        let transport = YabaiSocketTransport(path: server.path, timeout: 10, maxResponseBytes: 100_000)
        #expect(throws: YabaiError.responseTooLarge(limit: 100_000)) {
            _ = try transport.send(.query(.windows(.all)))
        }
    }

    @Test("the client decodes a real fixture over a real socket")
    func clientOverSocket() throws {
        let payload = try Fixture.windowsAll.data()
        let server = try UnixSocketServer { descriptor in
            _ = UnixSocketServer.write(payload, to: descriptor)
        }
        defer { server.shutdown() }

        let client = YabaiClient(transport: YabaiSocketTransport(path: server.path, timeout: 5))
        let windows = try client.windows()

        #expect(windows.count == 13)
        #expect(windows.filter { $0.hasFocus }.map { $0.id } == [577003])
    }
}

@Suite("Timeout clamping")
struct TimeoutClampingTests {
    static let clampingCases: [(input: TimeInterval, expected: TimeInterval)] = [
        (.infinity, YabaiSocketTransport.maximumTimeout),
        (-.infinity, YabaiSocketTransport.minimumTimeout),
        (0, YabaiSocketTransport.minimumTimeout),
        (-5, YabaiSocketTransport.minimumTimeout),
        (1e30, YabaiSocketTransport.maximumTimeout),
        (0.0005, YabaiSocketTransport.minimumTimeout),
        (7200, YabaiSocketTransport.maximumTimeout),
        (2, 2),
        (1.9999999, 1.9999999),
    ]

    @Test(
        "nonsense timeouts are folded into a finite positive window",
        arguments: TimeoutClampingTests.clampingCases
    )
    func clamping(input: TimeInterval, expected: TimeInterval) {
        #expect(YabaiSocketTransport.clampedTimeout(input) == expected)
        #expect(YabaiSocketTransport(path: "/dev/null", timeout: input).timeout == expected)
    }

    @Test("a NaN timeout falls back to the default")
    func notANumber() {
        #expect(YabaiSocketTransport.clampedTimeout(.nan) == YabaiSocketTransport.defaultTimeout)
    }

    @Test("microseconds that round to a full second carry into tv_sec", arguments: [
        (TimeInterval(1.9999999), 2, 0),
        (0.9999999, 1, 0),
        (1.5, 1, 500_000),
        (3600, 3600, 0),
        (0.001, 0, 1000),
    ] as [(TimeInterval, Int, Int32)])
    func timevalCarry(seconds: TimeInterval, expectedSeconds: Int, expectedMicroseconds: Int32) {
        let value = YabaiSocketTransport.socketTimeout(for: seconds)
        #expect(value.tv_sec == expectedSeconds)
        #expect(value.tv_usec == expectedMicroseconds)
        // EDOM territory: the kernel rejects a full second in tv_usec.
        #expect(value.tv_usec >= 0 && value.tv_usec < 1_000_000)
    }

    @Test("an all-zero timeval, which means block forever, is never produced")
    func neverBlocksForever() {
        for seconds in [YabaiSocketTransport.minimumTimeout, 1e-9, 0.0000001] {
            let value = YabaiSocketTransport.socketTimeout(for: seconds)
            #expect(value.tv_sec > 0 || value.tv_usec > 0)
        }
    }

    @Test("a timeout whose microseconds round to a full second is still usable")
    func microsecondCarry() throws {
        // 1.9999999s rounds to 1s + 1_000_000us, which setsockopt rejects with
        // EDOM unless the carry is folded into tv_sec.
        let server = try UnixSocketServer { descriptor in
            _ = UnixSocketServer.write(Data("[]".utf8), to: descriptor)
        }
        defer { server.shutdown() }

        let transport = YabaiSocketTransport(path: server.path, timeout: 1.9999999)
        #expect(try transport.send(.query(.displays)) == Data("[]".utf8))
    }
}

@Suite("SIGPIPE protection")
struct SignalProtectionTests {
    /// The regression gate. Deleting SO_NOSIGPIPE leaves every behavioural test
    /// passing, because a write to a hung-up peer kills the process instead of
    /// failing an assertion.
    @Test("every socket the transport opens has SO_NOSIGPIPE set")
    func socketsAreConfiguredAgainstSIGPIPE() throws {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        try #require(descriptor >= 0)
        defer { close(descriptor) }

        try YabaiSocketTransport(path: "/dev/null", timeout: 3).configure(descriptor)

        var enabled: Int32 = 0
        var size = socklen_t(MemoryLayout<Int32>.size)
        #expect(getsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &enabled, &size) == 0)
        #expect(enabled != 0, "a peer hanging up mid-write would kill the process")

        for option in [SO_RCVTIMEO, SO_SNDTIMEO] {
            var backstop = timeval()
            var length = socklen_t(MemoryLayout<timeval>.size)
            #expect(getsockopt(descriptor, SOL_SOCKET, option, &backstop, &length) == 0)
            #expect(backstop.tv_sec == 3)
        }
    }

    /// Complements the gate above with the real behaviour. Whether the server
    /// wins the accept-then-close race is up to the scheduler, so a run in
    /// which it never does asserts nothing rather than failing.
    @Test("a peer that hangs up mid-write throws instead of killing the process")
    func hangUpDoesNotRaiseSIGPIPE() throws {
        let server = try UnixSocketServer(readsRequest: false) { _ in }
        defer { server.shutdown() }

        let transport = YabaiSocketTransport(path: server.path, timeout: 2)
        var observed: YabaiError?
        var attempts = 0
        while observed == nil && attempts < 500 {
            attempts += 1
            do {
                _ = try transport.send(.query(.displays))
            } catch let error as YabaiError {
                switch error {
                case .writeFailed, .connectionClosed: observed = error
                default: break // the race landed elsewhere; go again
                }
            }
        }

        // Which errno the peer teardown produces depends on how the race lands,
        // so only the thrown error is contractual, not the code.
        guard case .writeFailed(let code)? = observed else { return }
        #expect([EPIPE, ENOTCONN, ECONNRESET].contains(code), "unexpected errno \(code)")
    }
}
