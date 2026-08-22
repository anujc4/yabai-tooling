import Darwin
import Foundation

public enum YabaiError: Error, Hashable, Sendable {
    case socketPathTooLong(String)
    case socketCreationFailed(code: Int32)
    case socketOptionFailed(code: Int32)
    case connectionFailed(path: String, code: Int32)
    case connectionClosed
    case writeFailed(code: Int32)
    case readFailed(code: Int32)
    case waitFailed(code: Int32)
    case responseTooLarge(limit: Int)
    case timedOut
    case remoteFailure(String)
    case invalidWindowIdentifier(Int)
    case argumentContainsDelimiter
    case decodingFailed(String)
}

extension YabaiError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .socketPathTooLong(let path):
            "yabai socket path too long for sockaddr_un: \(path)"
        case .socketCreationFailed(let code):
            "could not create unix socket: \(Self.message(code))"
        case .socketOptionFailed(let code):
            "could not set socket options: \(Self.message(code))"
        case .connectionFailed(let path, let code):
            "could not connect to \(path): \(Self.message(code))"
        case .connectionClosed:
            "yabai closed the connection before the request was written"
        case .writeFailed(let code):
            "write to yabai failed: \(Self.message(code))"
        case .readFailed(let code):
            "read from yabai failed: \(Self.message(code))"
        case .waitFailed(let code):
            "waiting on the yabai socket failed: \(Self.message(code))"
        case .responseTooLarge(let limit):
            "yabai response exceeded the \(limit) byte limit"
        case .timedOut:
            "yabai did not respond before the timeout elapsed"
        case .remoteFailure(let message):
            "yabai reported: \(message)"
        case .argumentContainsDelimiter:
            "a command argument contains a NUL, which is the argv delimiter"
        case .invalidWindowIdentifier(let id):
            "not a usable yabai window id: \(id)"
        case .decodingFailed(let detail):
            "could not decode yabai response: \(detail)"
        }
    }

    // strerror keeps a shared static buffer for unknown codes; the _r form is
    // the only one safe to call from the event loop's threads.
    private static func message(_ code: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        let status = buffer.withUnsafeMutableBufferPointer { pointer -> Int32 in
            guard let base = pointer.baseAddress else { return -1 }
            return strerror_r(code, base, pointer.count)
        }
        guard status == 0 else { return "errno \(code)" }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
