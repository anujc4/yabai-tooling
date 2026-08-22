/// Identity of a stack: the (space, frame) tuple. Two independent stacks can
/// live in one space as separate bsp leaves, and the members of one stack share
/// a byte-identical frame (SPEC 2).
public struct StackKey: Hashable, Sendable {
    public let space: Int
    public let frame: FrameKey

    public init(space: Int, frame: FrameKey) {
        self.space = space
        self.frame = frame
    }
}

/// A frame reduced to a hashable key. Raw `Double`s are a poor dictionary key:
/// NaN is equal to nothing, so a NaN-bearing frame would be unreachable in the
/// table, and exact bit equality makes grouping hostage to the last decimal.
/// Coordinates are quantised to milli-points instead, giving total equality.
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

    // Int64.min is reserved for NaN so that two NaN frames group together
    // rather than vanishing; infinities saturate one step inside it.
    static func quantise(_ value: Double) -> Int64 {
        guard !value.isNaN else { return Int64.min }
        let scaled = (value * scale).rounded()
        if scaled >= Double(Int64.max) { return Int64.max }
        if scaled <= Double(Int64.min) { return Int64.min + 1 }
        return Int64(scaled)
    }
}

/// Ordered on the quantised key rather than on the raw frame, so the ordering
/// stays a strict weak ordering even for a NaN-bearing frame. Exists so a
/// reconciliation diff can report keys in a stable order without the caller
/// having kept the stacks they came from.
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

/// One detected stack on a visible space. `Equatable` so two refreshes can be
/// diffed; `activeWindowID` is optional because a stack whose space is not the
/// focused one legitimately has no active member (SPEC 5).
public struct Stack: Hashable, Sendable {
    public let space: Int
    public let display: Int
    public let frame: YabaiFrame

    /// Ascending `stackIndex`; yabai returns members descending (SPEC 3).
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
