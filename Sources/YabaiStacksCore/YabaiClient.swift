import Foundation

public struct YabaiClient: Sendable {
    private let transport: any YabaiTransport

    public init(transport: any YabaiTransport) {
        self.transport = transport
    }

    public func windows(_ scope: YabaiQuery.WindowScope = .all) throws -> [YabaiWindow] {
        try query(.windows(scope))
    }

    public func spaces(_ scope: YabaiQuery.SpaceScope = .all) throws -> [YabaiSpace] {
        try query(.spaces(scope))
    }

    public func displays() throws -> [YabaiDisplay] {
        try query(.displays)
    }

    public func focusWindow(id: Int) throws {
        guard id > 0 else { throw YabaiError.invalidWindowIdentifier(id) }
        _ = try transport.send(.focusWindow(id: id))
    }

    public func addSignal(_ event: YabaiSignalEvent, notifying executable: String, socket: String) throws {
        _ = try transport.send(.addSignal(event: event, notifying: executable, socket: socket))
    }

    /// Cleanup runs on a signal handler: removing a signal we never added is not a failure.
    public func removeSignal(_ event: YabaiSignalEvent) {
        _ = try? transport.send(.removeSignal(event: event))
    }

    private func query<Element: Decodable>(_ query: YabaiQuery) throws -> [Element] {
        let data = try transport.send(.query(query))
        do {
            return try JSONDecoder().decode([Element].self, from: data)
        } catch {
            throw YabaiError.decodingFailed(String(describing: error))
        }
    }
}
