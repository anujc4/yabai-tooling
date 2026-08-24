import Foundation

/// The yabai events worth a refresh. Anything that can add, remove, move or
/// re-stack a window, plus the ones that change which space is visible.
public enum YabaiSignalEvent: String, Hashable, Sendable, CaseIterable {
    case applicationLaunched = "application_launched"
    case applicationTerminated = "application_terminated"
    case applicationFrontSwitched = "application_front_switched"
    case windowCreated = "window_created"
    case windowDestroyed = "window_destroyed"
    case windowFocused = "window_focused"
    case windowMoved = "window_moved"
    case windowResized = "window_resized"
    case windowMinimized = "window_minimized"
    case windowDeminimized = "window_deminimized"
    case spaceChanged = "space_changed"
    case displayChanged = "display_changed"
    case missionControlEnter = "mission_control_enter"
    case missionControlExit = "mission_control_exit"

    /// Mission Control is the one thing yabai reports that is not a reason to
    /// re-query: the stacks have not changed, only their visibility should.
    public var isMissionControl: Bool {
        self == .missionControlEnter || self == .missionControlExit
    }

    public static let labelPrefix = "yabai-stacks."

    /// Derived, never supplied by a caller. The user's own signals live in the
    /// same table, so a label this program can spell is a label it could later
    /// remove; deriving every one of them makes that impossible.
    public var label: String { "\(Self.labelPrefix)\(rawValue)" }
}

/// What a wake-up down the notification socket means. It lives in Core rather
/// than in the daemon because the executable target has no tests: the routing
/// mutated freely while the suite stayed green as long as it was a `switch` in
/// `main.swift`.
public enum WakeAction: Hashable, Sendable, CaseIterable {
    case refresh
    case hide
    case show

    /// An unknown or absent name refreshes rather than being dropped: a wake-up
    /// carries no promise of a name, and a yabai that adds an event must not
    /// silently stop repainting.
    public static func action(for name: String?) -> WakeAction {
        guard let event = name.flatMap(YabaiSignalEvent.init(rawValue:)), event.isMissionControl else {
            return .refresh
        }
        return event == .missionControlEnter ? .hide : .show
    }
}

public enum ExecutablePath {
    /// argv[0] is whatever the caller typed, so a PATH-launched daemon sees a
    /// bare "yabai-stacks" that URL(fileURLWithPath:) would resolve against the
    /// working directory. yabai would then exec a file that does not exist and
    /// every event would be silently lost.
    public static func resolved(argv0: String?) -> String {
        var size = UInt32(4096)
        var buffer = [CChar](repeating: 0, count: Int(size))
        if _NSGetExecutablePath(&buffer, &size) == 0 {
            let path = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            if !path.isEmpty {
                return URL(fileURLWithPath: path).standardizedFileURL.path
            }
        }
        return argv0 ?? "yabai-stacks"
    }
}

enum ShellQuoting {
    /// yabai hands a signal action to a shell, so the one value we interpolate
    /// — our own executable path — is single-quoted with embedded quotes broken
    /// out. Nothing else in this program reaches a shell.
    static func singleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
