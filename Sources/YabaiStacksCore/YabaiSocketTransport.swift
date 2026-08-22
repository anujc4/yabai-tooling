import Darwin
import Dispatch
import Foundation

public struct YabaiSocketTransport: YabaiTransport {
    public static let socketPathEnvironmentKey = "YABAI_SOCKET"
    public static let defaultTimeout: TimeInterval = 2
    public static let minimumTimeout: TimeInterval = 0.001
    public static let maximumTimeout: TimeInterval = 3600
    public static let defaultMaxResponseBytes = 8 * 1024 * 1024

    public let path: String

    /// Budget for the whole request, not a per-read idle timer: a server that
    /// dribbles bytes forever must still be cut off at `timeout`.
    public let timeout: TimeInterval

    public let maxResponseBytes: Int

    private static let readChunkSize = 64 * 1024

    public init(
        path: String? = nil,
        timeout: TimeInterval = YabaiSocketTransport.defaultTimeout,
        maxResponseBytes: Int = YabaiSocketTransport.defaultMaxResponseBytes
    ) {
        self.path = path ?? Self.defaultPath()
        self.timeout = Self.clampedTimeout(timeout)
        self.maxResponseBytes = max(1, maxResponseBytes)
    }

    /// Zero, negative and non-finite timeouts all mean "block forever" to the
    /// kernel, and `UInt64(.infinity)` traps, so every value is folded into a
    /// finite, strictly positive window before it can reach a deadline.
    public static func clampedTimeout(_ timeout: TimeInterval) -> TimeInterval {
        guard !timeout.isNaN else { return defaultTimeout }
        guard timeout.isFinite else { return timeout > 0 ? maximumTimeout : minimumTimeout }
        return min(max(timeout, minimumTimeout), maximumTimeout)
    }

    public static func defaultPath(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        if let override = environment[socketPathEnvironmentKey], !override.isEmpty {
            return override
        }
        let user = environment["USER"].flatMap { $0.isEmpty ? nil : $0 } ?? NSUserName()
        return "/tmp/yabai_\(user).socket"
    }

    public func send(_ command: YabaiCommand) throws -> Data {
        let deadline = Deadline(after: timeout)

        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw YabaiError.socketCreationFailed(code: errno) }
        defer { close(descriptor) }

        try configure(descriptor)
        try openConnection(on: descriptor)
        try writeAll(YabaiWireFormat.encode(command), to: descriptor, before: deadline)
        return try YabaiWireFormat.validate(response: readToEndOfFile(from: descriptor, before: deadline))
    }

    /// Socket options are set exactly once, while the socket is still fresh:
    /// Darwin rejects `setsockopt` with EINVAL once the peer has hung up, and
    /// yabai answers by writing and immediately closing.
    func configure(_ descriptor: Int32) throws {
        var enabled: Int32 = 1
        guard setsockopt(
            descriptor, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size)
        ) == 0 else {
            throw YabaiError.socketOptionFailed(code: errno)
        }

        // Backstop under the poll-based deadline, not the deadline itself.
        var value = Self.socketTimeout(for: timeout)
        let size = socklen_t(MemoryLayout<timeval>.size)
        for option in [SO_RCVTIMEO, SO_SNDTIMEO] {
            guard setsockopt(descriptor, SOL_SOCKET, option, &value, size) == 0 else {
                throw YabaiError.socketOptionFailed(code: errno)
            }
        }
    }

    static func socketTimeout(for seconds: TimeInterval) -> timeval {
        var whole = seconds.rounded(.down)
        var micro = ((seconds - whole) * 1_000_000).rounded()
        // Rounding can land on a full second, which the kernel rejects with EDOM.
        if micro >= 1_000_000 {
            micro -= 1_000_000
            whole += 1
        }
        // An all-zero timeval means "block forever".
        if whole == 0 && micro == 0 { micro = 1 }
        return timeval(tv_sec: Int(whole), tv_usec: suseconds_t(micro))
    }

    private func waitUntilReady(_ descriptor: Int32, for events: Int32, before deadline: Deadline) throws {
        while true {
            let remaining = deadline.remaining
            guard remaining > 0 else { throw YabaiError.timedOut }

            var watched = pollfd(fd: descriptor, events: Int16(events), revents: 0)
            let ready = poll(&watched, 1, max(1, Int32((remaining * 1000).rounded(.up))))
            if ready > 0 { return }
            if ready == 0 { throw YabaiError.timedOut }
            if errno == EINTR { continue }
            throw YabaiError.waitFailed(code: errno)
        }
    }

    private func openConnection(on descriptor: Int32) throws {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)

        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count < capacity else { throw YabaiError.socketPathTooLong(path) }
        withUnsafeMutablePointer(to: &address.sun_path) { field in
            field.withMemoryRebound(to: CChar.self, capacity: capacity) { destination in
                for (offset, byte) in bytes.enumerated() { destination[offset] = CChar(bitPattern: byte) }
                destination[bytes.count] = 0
            }
        }

        while true {
            let status = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                    Darwin.connect(descriptor, generic, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            if status == 0 { return }
            if errno == EINTR { continue }
            throw YabaiError.connectionFailed(path: path, code: errno)
        }
    }

    private func writeAll(_ data: Data, to descriptor: Int32, before deadline: Deadline) throws {
        try data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var sent = 0
            while sent < buffer.count {
                try waitUntilReady(descriptor, for: POLLOUT, before: deadline)
                let written = Darwin.send(descriptor, base + sent, buffer.count - sent, 0)
                // errno is only meaningful once the call has actually failed.
                if written > 0 {
                    sent += written
                } else if written == 0 {
                    throw YabaiError.connectionClosed
                } else if errno == EINTR {
                    continue
                } else if errno == EAGAIN || errno == EWOULDBLOCK {
                    throw YabaiError.timedOut
                } else {
                    throw YabaiError.writeFailed(code: errno)
                }
            }
        }
    }

    private func readToEndOfFile(from descriptor: Int32, before deadline: Deadline) throws -> Data {
        var response = Data()
        var chunk = [UInt8](repeating: 0, count: Self.readChunkSize)
        while true {
            try waitUntilReady(descriptor, for: POLLIN, before: deadline)
            let read = chunk.withUnsafeMutableBytes { Darwin.recv(descriptor, $0.baseAddress, $0.count, 0) }
            if read > 0 {
                guard response.count + read <= maxResponseBytes else {
                    throw YabaiError.responseTooLarge(limit: maxResponseBytes)
                }
                response.append(contentsOf: chunk[0..<read])
            } else if read == 0 {
                return response
            } else if errno == EINTR {
                continue
            } else if errno == EAGAIN || errno == EWOULDBLOCK {
                throw YabaiError.timedOut
            } else {
                throw YabaiError.readFailed(code: errno)
            }
        }
    }
}

private struct Deadline {
    private let expiry: UInt64

    init(after seconds: TimeInterval) {
        expiry = DispatchTime.now().uptimeNanoseconds &+ UInt64((seconds * 1_000_000_000).rounded())
    }

    var remaining: TimeInterval {
        let now = DispatchTime.now().uptimeNanoseconds
        guard expiry > now else { return 0 }
        return TimeInterval(expiry - now) / 1_000_000_000
    }
}
