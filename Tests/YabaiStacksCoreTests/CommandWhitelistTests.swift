import Foundation
import Testing
@testable import YabaiStacksCore

/// R4: the layout must never change. `YabaiCommand` is the only thing that can
/// produce argv, so auditing every case of it audits the whole IPC surface.
@Suite("Command whitelist (R4)")
struct CommandWhitelistTests {
    /// Verbs and flags that would mutate the user's layout or yabai's
    /// configuration. Matching is on whole argv tokens: the read-only scope
    /// flags `--space` / `--display` are deliberately not the same tokens as the
    /// `space` / `display` domains that would move things around.
    static let forbiddenTokens: Set<String> = [
        "space", "display", "config", "rule",
        "--swap", "--warp", "--stack", "--toggle", "--resize", "--move",
        "--insert", "--balance", "--ratio", "--grid", "--layout", "--create",
        "--destroy", "--label", "--mirror", "--rotate", "--flip", "--gap",
        "--padding", "--close", "--minimize", "--deminimize", "--sub-layer",
        "--opacity", "--scratchpad",
    ]

    static let allowedFirstTokens: Set<String> = ["query", "window", "signal"]
    static let allowedQueryDomains: Set<String> = ["--windows", "--spaces", "--displays"]
    static let allowedQueryScopeFlags: Set<String> = ["--space", "--display"]

    /// Every constructible command. The switches below are tripwires: adding a
    /// case to any of these enums stops this file compiling until the new case
    /// is represented here and re-audited.
    static var everyCommand: [YabaiCommand] {
        let windowScopes: [YabaiQuery.WindowScope] = [.all, .currentSpace, .space(2), .currentDisplay, .display(1)]
        for scope in windowScopes {
            switch scope {
            case .all, .currentSpace, .space, .currentDisplay, .display: break
            }
        }

        let spaceScopes: [YabaiQuery.SpaceScope] = [.all, .currentDisplay, .display(1)]
        for scope in spaceScopes {
            switch scope {
            case .all, .currentDisplay, .display: break
            }
        }

        var queries: [YabaiQuery] = windowScopes.map(YabaiQuery.windows) + spaceScopes.map(YabaiQuery.spaces)
        queries.append(.displays)
        for query in queries {
            switch query {
            case .windows, .spaces, .displays: break
            }
        }

        var commands: [YabaiCommand] = queries.map(YabaiCommand.query)
        commands.append(contentsOf: [.focusWindow(id: 0), .focusWindow(id: 577003), .focusWindow(id: -1)])

        for event in YabaiSignalEvent.allCases {
            commands.append(.addSignal(event: event, notifying: "/usr/local/bin/yabai-stacks"))
            commands.append(.removeSignal(event: event))
        }
        for command in commands {
            switch command {
            case .query, .focusWindow, .addSignal, .removeSignal: break
            }
        }
        return commands
    }

    @Test("the surface is 9 query shapes, focus, and one signal pair per event")
    func surfaceSize() {
        let queries = Self.everyCommand.filter { if case .query = $0 { true } else { false } }
        let focuses = Self.everyCommand.filter { if case .focusWindow = $0 { true } else { false } }
        let signals = Self.everyCommand.filter { $0.argv.first == "signal" }

        #expect(queries.count == 9)
        #expect(focuses.count == 3)
        #expect(Set(queries.map(\.argv)).count == 9)
        #expect(signals.count == YabaiSignalEvent.allCases.count * 2)
    }

    /// The user keeps their own signals in yabairc. A label this program can
    /// spell is a label it could remove, so every label it emits is derived
    /// from our prefix and no API accepts one as an argument.
    @Test("removing a signal can only ever target our own namespace")
    func signalRemovalCannotTouchUserSignals() {
        for event in YabaiSignalEvent.allCases {
            let argv = YabaiCommand.removeSignal(event: event).argv
            #expect(argv.count == 3)
            #expect(argv[0] == "signal")
            #expect(argv[1] == "--remove")
            #expect(argv[2].hasPrefix(YabaiSignalEvent.labelPrefix))
        }
        #expect(
            YabaiCommand.removeSignal(event: .windowCreated).argv
                == ["signal", "--remove", "yabai-stacks.window_created"]
        )
    }

    @Test("every added signal is labelled inside our namespace")
    func addedSignalsAreLabelledOurs() {
        for event in YabaiSignalEvent.allCases {
            let argv = YabaiCommand.addSignal(event: event, notifying: "/usr/local/bin/yabai-stacks").argv
            let label = try? #require(argv.first { $0.hasPrefix("label=") })
            #expect(label?.hasPrefix("label=" + YabaiSignalEvent.labelPrefix) == true)
            #expect(argv.contains("event=" + event.rawValue))
        }
    }

    @Test("a signal action is our own executable and carries no other command")
    func signalActionIsOnlyOurBinary() {
        let argv = YabaiCommand.addSignal(event: .windowCreated, notifying: "/opt/bin/yabai-stacks").argv
        #expect(argv == [
            "signal", "--add",
            "event=window_created",
            "action='/opt/bin/yabai-stacks' --notify",
            "label=yabai-stacks.window_created",
        ])
    }

    @Test("signal commands never carry a layout-mutating domain")
    func signalCommandsAreNotLayout() {
        for command in Self.everyCommand where command.argv.first == "signal" {
            #expect(!command.argv.contains("window"))
            #expect(!command.argv.contains("--focus"))
            let offending = Set(command.argv).intersection(Self.forbiddenTokens)
            #expect(offending.isEmpty, "\(command.argv) contains \(offending)")
        }
    }

    @Test("no command contains a layout-mutating or configuration token")
    func noMutatingTokens() {
        for command in Self.everyCommand {
            let offending = Set(command.argv).intersection(Self.forbiddenTokens)
            #expect(offending.isEmpty, "\(command.argv) contains \(offending)")
        }
    }

    @Test("every command starts with query or window")
    func allowedVerbs() {
        for command in Self.everyCommand {
            let verb = command.argv.first
            #expect(verb.map(Self.allowedFirstTokens.contains) == true, "unexpected verb in \(command.argv)")
        }
    }

    @Test("window commands are exactly window --focus <integer>")
    func windowCommandShape() {
        for command in Self.everyCommand where command.argv.first == "window" {
            let argv = command.argv
            #expect(argv.count == 3)
            #expect(argv[1] == "--focus")
            #expect(Int(argv[2]) != nil)
        }
        #expect(YabaiCommand.focusWindow(id: 577003).argv == ["window", "--focus", "577003"])
    }

    @Test("query commands are a known domain plus at most one read-only scope")
    func queryCommandShape() {
        for command in Self.everyCommand where command.argv.first == "query" {
            let argv = command.argv
            guard argv.count >= 2 else {
                Issue.record("query command with no domain: \(argv)")
                continue
            }
            #expect(Self.allowedQueryDomains.contains(argv[1]))

            switch argv.count {
            case 2:
                break
            case 3:
                #expect(Self.allowedQueryScopeFlags.contains(argv[2]), "\(argv)")
            case 4:
                #expect(Self.allowedQueryScopeFlags.contains(argv[2]), "\(argv)")
                #expect(Int(argv[3]) != nil, "\(argv)")
            default:
                Issue.record("unexpected query arity \(argv.count): \(argv)")
            }
        }
    }

    @Test("the exhaustive query and focus argv set equals the expected whitelist")
    func exactArgvWhitelist() {
        let expected: Set<[String]> = [
            ["query", "--windows"],
            ["query", "--windows", "--space"],
            ["query", "--windows", "--space", "2"],
            ["query", "--windows", "--display"],
            ["query", "--windows", "--display", "1"],
            ["query", "--spaces"],
            ["query", "--spaces", "--display"],
            ["query", "--spaces", "--display", "1"],
            ["query", "--displays"],
            ["window", "--focus", "0"],
            ["window", "--focus", "577003"],
            ["window", "--focus", "-1"],
        ]
        // Signal commands are audited separately: they are parameterised by
        // event, so pinning them here would restate YabaiSignalEvent.allCases.
        let subject = Self.everyCommand.map(\.argv).filter { $0.first != "signal" }
        #expect(Set(subject) == expected)
    }

    @Test("the client only ever emits whitelisted argv")
    func clientEmitsOnlyWhitelistedArgv() throws {
        let transport = MockTransport(returning: "[]")
        let client = YabaiClient(transport: transport)

        _ = try client.windows()
        _ = try client.windows(.currentSpace)
        _ = try client.windows(.space(2))
        _ = try client.windows(.currentDisplay)
        _ = try client.windows(.display(1))
        _ = try client.spaces()
        _ = try client.spaces(.currentDisplay)
        _ = try client.spaces(.display(1))
        _ = try client.displays()
        try client.focusWindow(id: 577003)

        #expect(transport.recordedCalls.count == 10)
        for argv in transport.recordedCalls {
            #expect(Set(argv).intersection(Self.forbiddenTokens).isEmpty, "\(argv)")
            #expect(Self.allowedFirstTokens.contains(argv[0]))
        }
    }
}
