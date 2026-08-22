/// The complete set of messages this program is able to send to yabai (R4).
/// There is no case carrying a free-form command string, and `argv` is internal
/// so that outside this module a command can only be named, never spelled: the
/// whitelist is a compile-time property, not a runtime check.
public enum YabaiCommand: Hashable, Sendable {
    case query(YabaiQuery)
    case focusWindow(id: Int)

    var argv: [String] {
        switch self {
        case .query(let query):
            return query.argv
        case .focusWindow(let id):
            return ["window", "--focus", String(id)]
        }
    }
}

public enum YabaiQuery: Hashable, Sendable {
    case windows(WindowScope)
    case spaces(SpaceScope)
    case displays

    /// Scopes are split per domain because only these combinations keep yabai's
    /// response a JSON array; `--spaces --space` and `--displays --display`
    /// return a single object instead (verified against v7.1.24).
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
