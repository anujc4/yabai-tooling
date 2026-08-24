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
    private let readQueue = DispatchQueue(label: "yabai-stacks.notification-reads")

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
    public static func notify(path: String, event: String? = nil, timeout: TimeInterval = 1) throws {
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

        let payload = Array((event ?? "").utf8)
        // No event is sent as no bytes: the listener reads to EOF, so an empty
        // payload already means "nothing to say" without a sentinel byte.
        if !payload.isEmpty {
            _ = payload.withUnsafeBytes { send(fd, $0.baseAddress, $0.count, 0) }
        }
    }

    /// True when something is already accepting on `path`. A stale file left by
    /// a killed process refuses the connection and is safe to reclaim. The probe
    /// is a real wake-up rather than a peek: connecting is the only way to tell
    /// the two apart, and a spurious eventless refresh is harmless.
    public static func isServed(path: String) -> Bool {
        (try? notify(path: path, timeout: 1)) != nil
    }

    /// How long one peer may take to say its piece. A `--notify` connects and
    /// writes immediately, so this only ever expires for a peer that has gone
    /// silent, and it bounds how long such a peer can hold up the queue.
    public static let readDeadline: TimeInterval = 0.2

    /// An event name is a `YabaiSignalEvent` raw value; anything longer is not
    /// one, and reading it would only delay the events behind it.
    static let maximumPayloadBytes = 256

    /// Calls `onEvent` once per connection, on a background thread. The caller
    /// is responsible for hopping to whatever queue it needs.
    public func listen(onEvent: @escaping @Sendable (String?) -> Void) throws {
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
                // Reading happens off the accept thread, so a silent peer
                // cannot stall the loop and leave the daemon deaf at 0% CPU,
                // and on a *serial* queue, so events are delivered in the order
                // they were accepted. A concurrent queue reorders them:
                // `accept` returns when the peer's `connect` completes, but a
                // real wake-up is a whole process launch before its `send`, so
                // a connection accepted first can be read last. Mission Control
                // enter/exit is a toggle, so one inversion parks the strips off
                // screen until the user opens Mission Control again.
                readQueue.async {
                    let name = Self.readEventName(from: client)
                    close(client)
                    onEvent(name)
                }
            }
        }
    }

    /// SOCK_STREAM carries no framing, so one `recv` is not one message even
    /// for twenty bytes: reading to EOF is the only way to know the name is
    /// whole. A truncated name decodes to something no `YabaiSignalEvent`
    /// matches, which would silently demote a Mission Control enter to an
    /// ordinary refresh. The deadline is absolute rather than the per-call idle
    /// timer `SO_RCVTIMEO` gives, which a dribbling peer can rearm for ever.
    static func readEventName(from client: Int32) -> String? {
        let expiry = DispatchTime.now().uptimeNanoseconds
            &+ UInt64((readDeadline * 1_000_000_000).rounded())
        var payload: [UInt8] = []
        var chunk = [UInt8](repeating: 0, count: 64)

        while payload.count < maximumPayloadBytes {
            let now = DispatchTime.now().uptimeNanoseconds
            guard expiry > now else { break }
            let remaining = Int32(((TimeInterval(expiry - now) / 1_000_000_000) * 1000).rounded(.up))

            var watched = pollfd(fd: client, events: Int16(POLLIN), revents: 0)
            let ready = poll(&watched, 1, max(1, remaining))
            if ready < 0 {
                if errno == EINTR { continue }
                break
            }
            guard ready > 0 else { break }

            let read = chunk.withUnsafeMutableBytes { recv(client, $0.baseAddress, $0.count, 0) }
            if read > 0 {
                payload.append(contentsOf: chunk[0..<read])
            } else if read == 0 {
                break
            } else if errno == EINTR {
                continue
            } else {
                break
            }
        }

        guard !payload.isEmpty else { return nil }
        return String(decoding: payload.prefix(maximumPayloadBytes), as: UTF8.self)
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
