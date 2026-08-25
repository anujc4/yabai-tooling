public struct StackDetector: Sendable {
    public static let defaultMinStackSize = 2

    /// Not clamped here: `Configuration.validate()` is the single gate for ranges.
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

        // Dictionary iteration order is not stable across runs; the reconciler diffs these.
        return stacks.sorted(by: Self.precedes)
    }

    private struct Group {
        let display: Int
        var members: [YabaiWindow]
    }

    /// `is-visible` reflects the window's space, not its place in the stack (SPEC 4, 6).
    private static func isStackMember(_ window: YabaiWindow) -> Bool {
        window.stackIndex >= 1 && !window.isFloating && !window.isMinimized && !window.isHidden
    }

    private static func precedes(_ lhs: Stack, _ rhs: Stack) -> Bool {
        let left = lhs.key.frame
        let right = rhs.key.frame
        return (lhs.display, lhs.space, left.y, left.x, left.w, left.h)
            < (rhs.display, rhs.space, right.y, right.x, right.w, right.h)
    }
}
