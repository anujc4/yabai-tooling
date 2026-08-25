import Foundation

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

    /// The one report that is not a reason to re-query: only visibility changes.
    public var isMissionControl: Bool {
        self == .missionControlEnter || self == .missionControlExit
    }

    public static let labelPrefix = "yabai-stacks."

    /// Derived, never supplied by a caller: the user's own signals share this table,
    /// so a label this program can spell is one it could later remove.
    public var label: String { "\(Self.labelPrefix)\(rawValue)" }
}

/// In Core rather than in the daemon because the executable target has no tests.
public enum WakeAction: Hashable, Sendable, CaseIterable {
    case refresh
    case hide
    case show

    /// An unknown or absent name refreshes rather than being dropped.
    public static func action(for name: String?) -> WakeAction {
        guard let event = name.flatMap(YabaiSignalEvent.init(rawValue:)), event.isMissionControl else {
            return .refresh
        }
        return event == .missionControlEnter ? .hide : .show
    }
}

public enum ExecutablePath {
    /// argv[0] is whatever the caller typed, so a PATH-launched daemon would hand yabai
    /// a bare name that resolves against the working directory instead.
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
    /// yabai hands a signal action to a shell; our own path is the only value we
    /// interpolate, and nothing else in this program reaches a shell.
    static func singleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
