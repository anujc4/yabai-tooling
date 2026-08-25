import Foundation

/// Takes a `YabaiCommand`, never argv, so R4's whitelist stays compile-time.
public protocol YabaiTransport: Sendable {
    func send(_ command: YabaiCommand) throws -> Data
}
