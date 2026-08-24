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
            // The tripwire for the signal table: a new event has to be named
            // here, and naming it is the moment to ask whether the action it
            // will register is still read-only.
            switch event {
            case .applicationLaunched, .applicationTerminated, .applicationFrontSwitched,
                 .windowCreated, .windowDestroyed, .windowFocused, .windowMoved, .windowResized,
                 .windowMinimized, .windowDeminimized, .spaceChanged, .displayChanged,
                 .missionControlEnter, .missionControlExit:
                break
            }
            commands.append(.addSignal(event: event, notifying: "/usr/local/bin/yabai-stacks", socket: "/tmp/s.sock"))
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
            let argv = YabaiCommand.addSignal(event: event, notifying: "/usr/local/bin/yabai-stacks", socket: "/tmp/s.sock").argv
            let label = try? #require(argv.first { $0.hasPrefix("label=") })
            #expect(label?.hasPrefix("label=" + YabaiSignalEvent.labelPrefix) == true)
            #expect(argv.contains("event=" + event.rawValue))
        }
    }

    @Test("a signal action is our own executable and carries no other command")
    func signalActionIsOnlyOurBinary() {
        let argv = YabaiCommand.addSignal(
            event: .windowCreated,
            notifying: "/opt/bin/yabai-stacks",
            socket: "/tmp/s.sock"
        ).argv
        #expect(argv == [
            "signal", "--add",
            "event=window_created",
            "action='/opt/bin/yabai-stacks' --notify --socket '/tmp/s.sock' --event window_created",
            "label=yabai-stacks.window_created",
        ])
    }

    /// The action carries the event name so the daemon can tell a Mission
    /// Control enter from a reason to re-query. It is the only unquoted value in
    /// the action, which is safe only because it comes from the enum's own raw
    /// values and never from anything a user can type.
    @Test("the action names its own event, and every event name is shell-inert")
    func signalActionCarriesItsEvent() {
        for event in YabaiSignalEvent.allCases {
            let argv = YabaiCommand.addSignal(
                event: event, notifying: "/opt/bin/yabai-stacks", socket: "/tmp/s.sock"
            ).argv
            #expect(argv[3].hasSuffix(" --event \(event.rawValue)"))
            #expect(event.rawValue.allSatisfy { $0.isLowercase || $0 == "_" })
        }
    }

    @Test("Mission Control is registered like any other event and mutates nothing")
    func missionControlSignalsAreOrdinary() {
        let missionControl = YabaiSignalEvent.allCases.filter(\.isMissionControl)
        #expect(Set(missionControl) == [.missionControlEnter, .missionControlExit])
        #expect(YabaiSignalEvent.allCases.filter { !$0.isMissionControl }.count == 12)

        for event in missionControl {
            let add = YabaiCommand.addSignal(
                event: event, notifying: "/opt/bin/yabai-stacks", socket: "/tmp/s.sock"
            ).argv
            #expect(add[2] == "event=" + event.rawValue)
            #expect(add[3].contains("--notify"))
            #expect(add.last == "label=" + YabaiSignalEvent.labelPrefix + event.rawValue)
            #expect(Set(add).intersection(Self.forbiddenTokens).isEmpty)
            #expect(
                YabaiCommand.removeSignal(event: event).argv
                    == ["signal", "--remove", "yabai-stacks." + event.rawValue]
            )
        }
    }

    /// yabai hands a signal action to a shell, so this quoting is the single
    /// most load-bearing line for R4. Deleting the escaping used to leave the
    /// whole suite green.
    @Test("a hostile path cannot break out of the quoted action")
    func shellQuotingContainsHostilePaths() {
        let hostile = "/tmp/e'; rm -rf ~; echo '"
        let quoted = ShellQuoting.singleQuoted(hostile)

        // Reconstructing the original from the quoted form is the property that
        // matters: what the shell parses back must be exactly the input.
        #expect(Self.shellParse(quoted) == hostile)

        #expect(quoted.hasPrefix("'"))
        #expect(quoted.hasSuffix("'"))

        // Every bare quote in the input becomes a closed-then-escaped sequence,
        // so the quote count stays even and the string cannot end early.
        #expect(quoted.filter { $0 == "'" }.count % 2 == 0)

        for injection in ["`whoami`", "$(id)", "; reboot", "\n yabai -m space --destroy", "$HOME"] {
            let safe = ShellQuoting.singleQuoted("/tmp/x" + injection)
            #expect(safe.hasPrefix("'/tmp/x"))
            #expect(safe.hasSuffix("'"))
            #expect(safe.filter { $0 == "'" }.count % 2 == 0)
        }
    }

    /// Mirrors how a POSIX shell reads a single-quoted word: everything is
    /// literal until the next quote, and '\'' re-opens after an escaped one.
    static func shellParse(_ quoted: String) -> String {
        var out = ""
        var inQuotes = false
        var iterator = quoted.makeIterator()
        var pending: Character?
        while let character = pending ?? iterator.next() {
            pending = nil
            if character == "'" {
                inQuotes.toggle()
            } else if character == "\\", !inQuotes {
                if let escaped = iterator.next() { out.append(escaped) }
            } else {
                out.append(character)
            }
        }
        return out
    }

    @Test("a hostile socket path is quoted with the same rule")
    func hostileSocketPathIsQuoted() {
        let argv = YabaiCommand.addSignal(
            event: .windowCreated,
            notifying: "/opt/bin/yabai-stacks",
            socket: "/tmp/s'; rm -rf ~; echo '.sock"
        ).argv
        let action = argv[3]

        #expect(action.hasPrefix("action='/opt/bin/yabai-stacks' --notify --socket '"))
        #expect(action.hasSuffix("' --event window_created"))
        #expect(action.filter { $0 == "'" }.count % 2 == 0)
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
