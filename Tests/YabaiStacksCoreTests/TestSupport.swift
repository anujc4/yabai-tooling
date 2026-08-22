import Foundation
@testable import YabaiStacksCore

enum Fixture: String, CaseIterable {
    case windowsAll = "windows-all"
    case windowsStackVisible = "windows-stack-visible"
    case spaces = "spaces"
    case displays = "displays"

    enum Failure: Error { case missing(String) }

    func data() throws -> Data {
        guard let url = Bundle.module.url(
            forResource: rawValue,
            withExtension: "json",
            subdirectory: "Fixtures"
        ) else {
            throw Failure.missing(rawValue)
        }
        return try Data(contentsOf: url)
    }
}

/// The only transport used outside `SocketTransportTests`, which binds its own
/// socket. Nothing in this target ever touches `/tmp/yabai_$USER.socket`.
final class MockTransport: YabaiTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var commands: [YabaiCommand] = []
    private let respond: @Sendable (YabaiCommand) throws -> Data

    init(respond: @escaping @Sendable (YabaiCommand) throws -> Data) {
        self.respond = respond
    }

    convenience init(returning data: Data) {
        self.init(respond: { _ in data })
    }

    convenience init(returning json: String) {
        self.init(returning: Data(json.utf8))
    }

    convenience init(throwing error: YabaiError) {
        self.init(respond: { _ in throw error })
    }

    var recordedCommands: [YabaiCommand] {
        lock.lock()
        defer { lock.unlock() }
        return commands
    }

    var recordedCalls: [[String]] { recordedCommands.map(\.argv) }

    var lastCall: [String]? { recordedCalls.last }

    func send(_ command: YabaiCommand) throws -> Data {
        lock.lock()
        commands.append(command)
        lock.unlock()
        return try respond(command)
    }
}
