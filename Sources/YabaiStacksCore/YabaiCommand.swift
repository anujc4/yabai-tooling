/// Every message this program can send to yabai (R4). `argv` is internal, so
/// outside this module a command can be named but never spelled.
public enum YabaiCommand: Hashable, Sendable {
    case query(YabaiQuery)
    case focusWindow(id: Int)

    /// On the whitelist because a signal changes what yabai notifies us about,
    /// never where a window sits.
    case addSignal(event: YabaiSignalEvent, notifying: String, socket: String)
    case removeSignal(event: YabaiSignalEvent)

    var argv: [String] {
        switch self {
        case .query(let query):
            return query.argv
        case .focusWindow(let id):
            return ["window", "--focus", String(id)]
        case .addSignal(let event, let executable, let socket):
            // The socket path is baked in: the child runs under yabai's environment,
            // which may not carry USER, and would derive a different path.
            return [
                "signal", "--add",
                "event=\(event.rawValue)",
                "action=\(ShellQuoting.singleQuoted(executable)) --notify --socket \(ShellQuoting.singleQuoted(socket)) --event \(event.rawValue)",
                "label=\(event.label)",
            ]
        case .removeSignal(let event):
            return ["signal", "--remove", event.label]
        }
    }
}

public enum YabaiQuery: Hashable, Sendable {
    case windows(WindowScope)
    case spaces(SpaceScope)
    case displays

    /// Only these scopes keep the response a JSON array (SPEC § Query response shapes).
    public enum WindowScope: Hashable, Sendable {
        case all
        case currentSpace
        case space(Int)
        case currentDisplay
        case display(Int)

        var argv: [String] {
            switch self {
            case .all: []
            case .currentSpace: ["--space"]
            case .space(let index): ["--space", String(index)]
            case .currentDisplay: ["--display"]
            case .display(let index): ["--display", String(index)]
            }
        }
    }

    public enum SpaceScope: Hashable, Sendable {
        case all
        case currentDisplay
        case display(Int)

        var argv: [String] {
            switch self {
            case .all: []
            case .currentDisplay: ["--display"]
            case .display(let index): ["--display", String(index)]
            }
        }
    }

    var argv: [String] {
        switch self {
        case .windows(let scope): ["query", "--windows"] + scope.argv
        case .spaces(let scope): ["query", "--spaces"] + scope.argv
        case .displays: ["query", "--displays"]
        }
    }
}
