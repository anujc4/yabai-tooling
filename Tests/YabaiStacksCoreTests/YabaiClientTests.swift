import Foundation
import Testing
@testable import YabaiStacksCore

@Suite("YabaiClient over an injected mock transport")
struct YabaiClientTests {
    @Test("query argv for every supported window scope", arguments: [
        (YabaiQuery.WindowScope.all, ["query", "--windows"]),
        (.currentSpace, ["query", "--windows", "--space"]),
        (.space(2), ["query", "--windows", "--space", "2"]),
        (.currentDisplay, ["query", "--windows", "--display"]),
        (.display(1), ["query", "--windows", "--display", "1"]),
    ])
    func windowScopeArgv(scope: YabaiQuery.WindowScope, expected: [String]) throws {
        let transport = MockTransport(returning: "[]")
        _ = try YabaiClient(transport: transport).windows(scope)
        #expect(transport.lastCall == expected)
    }

    @Test("query argv for every supported space scope", arguments: [
        (YabaiQuery.SpaceScope.all, ["query", "--spaces"]),
        (.currentDisplay, ["query", "--spaces", "--display"]),
        (.display(1), ["query", "--spaces", "--display", "1"]),
    ])
    func spaceScopeArgv(scope: YabaiQuery.SpaceScope, expected: [String]) throws {
        let transport = MockTransport(returning: "[]")
        _ = try YabaiClient(transport: transport).spaces(scope)
        #expect(transport.lastCall == expected)
    }

    @Test("displays query takes no scope")
    func displaysArgv() throws {
        let transport = MockTransport(returning: "[]")
        _ = try YabaiClient(transport: transport).displays()
        #expect(transport.lastCall == ["query", "--displays"])
    }

    @Test("focusWindow produces window --focus <id>")
    func focusArgv() throws {
        let transport = MockTransport(returning: Data())
        try YabaiClient(transport: transport).focusWindow(id: 577003)
        #expect(transport.lastCall == ["window", "--focus", "577003"])
        #expect(transport.recordedCalls.count == 1)
    }

    @Test("fixture payloads decode through the client")
    func decodesFixtures() throws {
        let windows = try YabaiClient(transport: MockTransport(returning: Fixture.windowsAll.data())).windows()
        #expect(windows.count == 13)
        #expect(windows.first(where: \.hasFocus)?.id == 577003)

        let stack = try YabaiClient(transport: MockTransport(returning: Fixture.windowsStackVisible.data()))
            .windows(.space(2))
        #expect(stack.map(\.stackIndex) == [4, 3, 2, 1])

        let spaces = try YabaiClient(transport: MockTransport(returning: Fixture.spaces.data())).spaces()
        #expect(spaces.filter(\.isVisible).map(\.index) == [5])

        let displays = try YabaiClient(transport: MockTransport(returning: Fixture.displays.data())).displays()
        #expect(displays.map(\.index) == [1])
    }

    @Test("transport errors surface unchanged")
    func transportErrorsPropagate() {
        let client = YabaiClient(transport: MockTransport(throwing: .remoteFailure("unknown command")))
        #expect(throws: YabaiError.remoteFailure("unknown command")) { _ = try client.windows() }
        #expect(throws: YabaiError.remoteFailure("unknown command")) { try client.focusWindow(id: 1) }

        let timingOut = YabaiClient(transport: MockTransport(throwing: .timedOut))
        #expect(throws: YabaiError.timedOut) { _ = try timingOut.spaces() }
    }

    @Test("a non-positive window id is rejected without reaching the transport", arguments: [0, -1, Int.min])
    func rejectsNonPositiveWindowIds(id: Int) {
        let transport = MockTransport(returning: Data())
        let client = YabaiClient(transport: transport)

        #expect(throws: YabaiError.invalidWindowIdentifier(id)) { try client.focusWindow(id: id) }
        #expect(transport.recordedCommands.isEmpty)
    }

    @Test("malformed payloads become decodingFailed")
    func decodingErrors() throws {
        for payload in ["not json", "{}", "[{\"id\":1}]"] {
            let client = YabaiClient(transport: MockTransport(returning: payload))
            let error = try #require(throws: YabaiError.self) { _ = try client.windows() }
            guard case .decodingFailed = error else {
                Issue.record("expected decodingFailed, got \(error)")
                continue
            }
        }
    }

    @Test("the client issues exactly one message per call")
    func oneMessagePerCall() throws {
        let transport = MockTransport(returning: "[]")
        let client = YabaiClient(transport: transport)
        _ = try client.windows()
        _ = try client.spaces()
        _ = try client.displays()

        #expect(transport.recordedCalls == [
            ["query", "--windows"],
            ["query", "--spaces"],
            ["query", "--displays"],
        ])
    }
}
