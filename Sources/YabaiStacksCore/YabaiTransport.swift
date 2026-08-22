import Foundation

/// Takes a `YabaiCommand`, not argv: `YabaiCommand.argv` is internal, so no
/// caller outside this module can name a command that is not on the whitelist.
public protocol YabaiTransport: Sendable {
    func send(_ command: YabaiCommand) throws -> Data
}
