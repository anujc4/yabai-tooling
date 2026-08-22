/// Turns a window list and a space list into the stacks worth drawing.
public struct StackDetector: Sendable {
    public static let defaultMinStackSize = 2

    /// Stored verbatim: `Configuration.validate()` is the single gate that
    /// rejects out-of-range values, so the detector does not also clamp.
    public let minStackSize: Int

    public init(minStackSize: Int = StackDetector.defaultMinStackSize) {
        self.minStackSize = minStackSize
    }

    public init(configuration: Configuration) {
        self.init(minStackSize: configuration.minStackSize)
    }

    public func detect(windows: [YabaiWindow], spaces: [YabaiSpace]) -> [Stack] {
        let visibleSpaces = Dictionary(
            spaces.lazy.filter(\.isVisible).map { ($0.index, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var grouped: [StackKey: Group] = [:]
        for window in windows where Self.isStackMember(window) {
            guard let space = visibleSpaces[window.space] else { continue }
            let key = StackKey(space: window.space, frame: FrameKey(window.frame))
            grouped[key, default: Group(display: space.display, members: [])].members.append(window)
        }

        var stacks: [Stack] = []
        for (key, group) in grouped where group.members.count >= minStackSize {
            let ordered = group.members.sorted { ($0.stackIndex, $0.id) < ($1.stackIndex, $1.id) }
            guard let first = ordered.first else { continue }
            stacks.append(
                Stack(
                    space: key.space,
                    display: group.display,
                    frame: first.frame,
                    members: ordered,
                    activeWindowID: ordered.first(where: \.hasFocus)?.id
                )
            )
        }

        // Dictionary iteration order is not stable across runs; M4 diffs these.
        return stacks.sorted(by: Self.precedes)
    }

    private struct Group {
        let display: Int
        var members: [YabaiWindow]
    }

    /// `is-visible` is deliberately not consulted: it reflects the window's
    /// space, not its position in the stack (SPEC 4, SPEC 6).
    private static func isStackMember(_ window: YabaiWindow) -> Bool {
        window.stackIndex >= 1 && !window.isFloating && !window.isMinimized && !window.isHidden
    }

    /// Ordered on `FrameKey`, not on the raw frame: `Double` comparison is not a
    /// strict weak ordering once a coordinate is NaN, which would make the sort
    /// itself non-deterministic.
    private static func precedes(_ lhs: Stack, _ rhs: Stack) -> Bool {
        let left = lhs.key.frame
        let right = rhs.key.frame
        return (lhs.display, lhs.space, left.y, left.x, left.w, left.h)
            < (rhs.display, rhs.space, right.y, right.x, right.w, right.h)
    }
}
