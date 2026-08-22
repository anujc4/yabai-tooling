import Darwin
import Foundation

/// A yabai signal action runs a shell command, so the cheapest wake-up we can
/// arrange is a tiny process that connects here, writes nothing in particular
/// and exits. The daemon never polls; it blocks in `accept` until yabai fires.
public final class NotificationSocket: @unchecked Sendable {
    public let path: String
    private let lock = NSLock()
    private var descriptor: Int32 = -1
    private var listening = false

    public init(path: String) {
        self.path = path
    }

    public static func defaultPath(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        if let override = environment["YABAI_STACKS_SOCKET"], !override.isEmpty { return override }
        // NSTemporaryDirectory is per-user and mode 0700; /tmp is world
        // writable, so another process could pre-create the path or connect.
        let user = environment["USER"] ?? "unknown"
        return NSTemporaryDirectory() + "yabai-stacks_\(user).socket"
    }

    /// Sends one wake-up and returns. Used by the `--notify` path, which must
    /// stay fast: yabai runs it once per event and waits for it to exit.
    public static func notify(path: String, timeout: TimeInterval = 1) throws {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw YabaiError.socketCreationFailed(code: errno) }
        defer { close(fd) }

        var timeval = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeval, socklen_t(MemoryLayout<Darwin.timeval>.size))

        var address = sockaddr_un()
        try bind(path: path, into: &address)
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, size) }
        }
        guard result == 0 else { throw YabaiError.connectionFailed(path: path, code: errno) }

        var byte: UInt8 = 1
        _ = send(fd, &byte, 1, 0)
    }

    /// True when something is already accepting on `path`. A stale file left by
    /// a killed process refuses the connection and is safe to reclaim.
    public static func isServed(path: String) -> Bool {
        (try? notify(path: path, timeout: 0.25)) != nil
    }

    /// Calls `onEvent` once per connection, on a background thread. The caller
    /// is responsible for hopping to whatever queue it needs.
    public func listen(onEvent: @escaping @Sendable () -> Void) throws {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw YabaiError.socketCreationFailed(code: errno) }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        // A stale socket file outlives an ungraceful exit and would make bind
        // fail with EADDRINUSE forever.
        unlink(path)

        var address = sockaddr_un()
        try Self.bind(path: path, into: &address)
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, size) }
        }
        guard bound == 0 else {
            close(fd)
            throw YabaiError.connectionFailed(path: path, code: errno)
        }
        // bind() creates the filesystem node, and fchmod on the socket fd does
        // not reach it on Darwin, so the path is chmod'ed directly.
        _ = chmod(path, 0o600)
        guard Darwin.listen(fd, 32) == 0 else {
            close(fd)
            throw YabaiError.connectionFailed(path: path, code: errno)
        }

        lock.lock()
        descriptor = fd
        listening = true
        lock.unlock()

        Thread.detachNewThread { [weak self] in
            while true {
                let client = accept(fd, nil, nil)
                guard let self, self.isListening else {
                    if client >= 0 { close(client) }
                    return
                }
                guard client >= 0 else {
                    if errno == EINTR { continue }
                    return
                }
                // The connection itself is the wake-up. Reading first would let
                // any peer that connects and stays silent block the only accept
                // thread forever, leaving the daemon deaf at 0% CPU.
                close(client)
                onEvent()
            }
        }
    }

    private var isListening: Bool {
        lock.lock()
        defer { lock.unlock() }
        return listening
    }

    public func stop() {
        lock.lock()
        let fd = descriptor
        descriptor = -1
        listening = false
        lock.unlock()

        if fd >= 0 { close(fd) }
        unlink(path)
    }

    private static func bind(path: String, into address: inout sockaddr_un) throws {
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count < capacity else { throw YabaiError.socketPathTooLong(path) }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
    }
}
