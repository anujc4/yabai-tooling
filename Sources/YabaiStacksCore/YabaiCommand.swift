/// The complete set of messages this program is able to send to yabai (R4).
/// There is no case carrying a free-form command string, and `argv` is internal
/// so that outside this module a command can only be named, never spelled: the
/// whitelist is a compile-time property, not a runtime check.
public enum YabaiCommand: Hashable, Sendable {
    case query(YabaiQuery)
    case focusWindow(id: Int)

    /// Signals are not layout: adding one changes what yabai notifies us about,
    /// never where a window sits. The action is built from an executable path
    /// rather than taken as a string, and the label is derived from the event,
    /// so neither an arbitrary command nor another program's label is spellable.
    case addSignal(event: YabaiSignalEvent, notifying: String)
    case removeSignal(event: YabaiSignalEvent)

    var argv: [String] {
        switch self {
        case .query(let query):
            return query.argv
        case .focusWindow(let id):
            return ["window", "--focus", String(id)]
        case .addSignal(let event, let executable):
            return [
                "signal", "--add",
                "event=\(event.rawValue)",
                "action=\(ShellQuoting.singleQuoted(executable)) --notify",
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
