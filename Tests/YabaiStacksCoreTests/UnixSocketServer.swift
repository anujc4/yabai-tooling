import Darwin
import Foundation

/// A throwaway `AF_UNIX` server bound under `NSTemporaryDirectory()`, used to
/// exercise `YabaiSocketTransport` without going anywhere near the real yabai
/// socket. Reads one length-prefixed request, records the exact bytes, then
/// hands the connection to `respond`.
final class UnixSocketServer: @unchecked Sendable {
    enum Failure: Error {
        case create(Int32)
        case bind(Int32, String)
        case listen(Int32)
        case pathTooLong(String)
    }

    let path: String

    private let listener: Int32
    private let lock = NSLock()
    private var storedRequests: [Data] = []

    init(readsRequest: Bool = true, respond: @escaping @Sendable (Int32) -> Void) throws {
        path = NSTemporaryDirectory() + "ys-\(UUID().uuidString.prefix(8)).sock"

        listener = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listener >= 0 else { throw Failure.create(errno) }
        unlink(path)

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count < capacity else {
            close(listener)
            throw Failure.pathTooLong(path)
        }
        withUnsafeMutablePointer(to: &address.sun_path) { field in
            field.withMemoryRebound(to: CChar.self, capacity: capacity) { destination in
                for (offset, byte) in bytes.enumerated() { destination[offset] = CChar(bitPattern: byte) }
                destination[bytes.count] = 0
            }
        }

        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                bind(listener, generic, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else {
            let code = errno
            close(listener)
            throw Failure.bind(code, path)
        }
        guard listen(listener, 8) == 0 else {
            let code = errno
            close(listener)
            throw Failure.listen(code)
        }

        Thread.detachNewThread { [self] in serve(readsRequest: readsRequest, respond) }
    }

    var requests: [Data] {
        lock.lock()
        defer { lock.unlock() }
        return storedRequests
    }

    func shutdown() {
        close(listener)
        unlink(path)
    }

    /// Writes `data`, tolerating a client that has already hung up.
    static func write(_ data: Data, to descriptor: Int32) -> Bool {
        data.withUnsafeBytes { buffer -> Bool in
            guard let base = buffer.baseAddress else { return true }
            var sent = 0
            while sent < buffer.count {
                let written = Darwin.send(descriptor, base + sent, buffer.count - sent, 0)
                if written > 0 {
                    sent += written
                } else if written < 0 && errno == EINTR {
                    continue
                } else {
                    return false
                }
            }
            return true
        }
    }

    private func serve(readsRequest: Bool, _ respond: @escaping @Sendable (Int32) -> Void) {
        while true {
            let connection = accept(listener, nil, nil)
            guard connection >= 0 else {
                // A transient accept error must not retire the server for the
                // rest of the test; only a closed listener ends the loop.
                if errno == EINTR || errno == ECONNABORTED { continue }
                return
            }
            var enabled: Int32 = 1
            setsockopt(connection, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size))

            if readsRequest, let request = readFramedRequest(from: connection) {
                lock.lock()
                storedRequests.append(request)
                lock.unlock()
            }
            respond(connection)
            close(connection)
        }
    }

    private func readFramedRequest(from descriptor: Int32) -> Data? {
        guard let prefix = readExactly(4, from: descriptor) else { return nil }
        let length = prefix.withUnsafeBytes { Int(UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self))) }
        guard let payload = readExactly(length, from: descriptor) else { return nil }
        return prefix + payload
    }

    private func readExactly(_ count: Int, from descriptor: Int32) -> Data? {
        var buffer = Data()
        var scratch = [UInt8](repeating: 0, count: count)
        while buffer.count < count {
            let read = scratch.withUnsafeMutableBytes {
                recv(descriptor, $0.baseAddress, count - buffer.count, 0)
            }
            if read > 0 {
                buffer.append(contentsOf: scratch[0..<read])
            } else if read < 0 && errno == EINTR {
                continue
            } else {
                return nil
            }
        }
        return buffer
    }
}
