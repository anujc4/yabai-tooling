/// Identity of a stack: the (space, frame) tuple. One space can hold two of
/// them as separate bsp leaves, and one stack's members share a frame.
public struct StackKey: Hashable, Sendable {
    public let space: Int
    public let frame: FrameKey

    public init(space: Int, frame: FrameKey) {
        self.space = space
        self.frame = frame
    }
}

/// Quantised to milli-points: a raw `Double` key goes unreachable once a coordinate
/// is NaN, and bit equality makes grouping hostage to the last decimal.
public struct FrameKey: Hashable, Sendable {
    public static let scale: Double = 1000

    public let x: Int64
    public let y: Int64
    public let w: Int64
    public let h: Int64

    public init(_ frame: YabaiFrame) {
        x = Self.quantise(frame.x)
        y = Self.quantise(frame.y)
        w = Self.quantise(frame.w)
        h = Self.quantise(frame.h)
    }

    // Int64.min is reserved for NaN so two NaN frames group rather than vanish.
    static func quantise(_ value: Double) -> Int64 {
        guard !value.isNaN else { return Int64.min }
        let scaled = (value * scale).rounded()
        if scaled >= Double(Int64.max) { return Int64.max }
        if scaled <= Double(Int64.min) { return Int64.min + 1 }
        return Int64(scaled)
    }
}

/// Ordered on the quantised key, so the ordering stays strict-weak even for NaN.
extension FrameKey: Comparable {
    public static func < (lhs: FrameKey, rhs: FrameKey) -> Bool {
        (lhs.y, lhs.x, lhs.w, lhs.h) < (rhs.y, rhs.x, rhs.w, rhs.h)
    }
}

extension StackKey: Comparable {
    public static func < (lhs: StackKey, rhs: StackKey) -> Bool {
        (lhs.space, lhs.frame) < (rhs.space, rhs.frame)
    }
}

/// One detected stack on a visible space. A stack whose space is not the focused
/// one legitimately has no active member.
public struct Stack: Hashable, Sendable {
    public let space: Int
    public let display: Int
    public let frame: YabaiFrame

    /// Ascending `stackIndex`; yabai returns members descending.
    public let members: [YabaiWindow]

    public let activeWindowID: Int?

    public init(space: Int, display: Int, frame: YabaiFrame, members: [YabaiWindow], activeWindowID: Int?) {
        self.space = space
        self.display = display
        self.frame = frame
        self.members = members
        self.activeWindowID = activeWindowID
    }

    public var key: StackKey { StackKey(space: space, frame: FrameKey(frame)) }

    public var count: Int { members.count }

    public var activeMember: YabaiWindow? {
        guard let activeWindowID else { return nil }
        return members.first { $0.id == activeWindowID }
    }
}
