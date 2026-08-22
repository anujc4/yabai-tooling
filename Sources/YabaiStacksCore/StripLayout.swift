public enum StripSide: String, Hashable, Sendable, CaseIterable {
    case left
    case right
}

/// One stack's icon strip. Every rect is in the same coordinate space — yabai's
/// top-left-origin space as built, or AppKit's bottom-left-origin space after
/// `converted(toAppKitWithPrimaryDisplayHeight:)` flips the whole layout at
/// once. Nothing here mixes the two.
public struct StripLayout: Hashable, Sendable {
    public let side: StripSide
    public let frame: Rect

    /// In member order, left to right.
    public let icons: [Rect]
    public let windowIDs: [Int]

    /// Position of the focused member within the strip. Optional because a
    /// stack on a visible but unfocused space legitimately has none (SPEC 5).
    public let activeIndex: Int?

    // Internal so `icons` and `windowIDs` can never be handed in mismatched.
    init(side: StripSide, frame: Rect, icons: [Rect], windowIDs: [Int], activeIndex: Int?) {
        self.side = side
        self.frame = frame
        self.icons = icons
        self.windowIDs = windowIDs
        self.activeIndex = activeIndex
    }

    public var count: Int { windowIDs.count }

    public var activeWindowID: Int? { activeIndex.flatMap(windowID(forIcon:)) }

    public func iconRect(at index: Int) -> Rect? {
        icons.indices.contains(index) ? icons[index] : nil
    }

    public func windowID(forIcon index: Int) -> Int? {
        windowIDs.indices.contains(index) ? windowIDs[index] : nil
    }

    public func iconIndex(at point: Point) -> Int? {
        icons.firstIndex { $0.contains(point) }
    }

    public func windowID(at point: Point) -> Int? {
        iconIndex(at: point).flatMap(windowID(forIcon:))
    }

    /// Icon rects relative to `frame.origin`, which is what a click reported as
    /// `NSEvent.locationInWindow` is relative to once the panel sits on `frame`.
    public var localIcons: [Rect] {
        icons.map { $0.offsetBy(dx: -frame.minX, dy: -frame.minY) }
    }

    public func iconIndex(atLocal point: Point) -> Int? {
        iconIndex(at: Point(x: point.x + frame.minX, y: point.y + frame.minY))
    }

    public func windowID(atLocal point: Point) -> Int? {
        iconIndex(atLocal: point).flatMap(windowID(forIcon:))
    }

    public func converted(toAppKitWithPrimaryDisplayHeight height: Double) -> StripLayout {
        StripLayout(
            side: side,
            frame: Geometry.appKitRect(fromYabai: frame, primaryDisplayHeight: height),
            icons: icons.map { Geometry.appKitRect(fromYabai: $0, primaryDisplayHeight: height) },
            windowIDs: windowIDs,
            activeIndex: activeIndex
        )
    }
}

public enum StripGeometry {
    public static func size(iconCount: Int, configuration: Configuration) -> Size {
        let count = Double(max(0, iconCount))
        return Size(
            width: configuration.padding * 2
                + count * configuration.iconSize
                + max(0, count - 1) * configuration.iconSpacing,
            height: configuration.padding * 2 + configuration.iconSize
        )
    }

    /// `.auto` goes right only when the stack's horizontal centre is strictly
    /// past its own display's centre, so a stack centred exactly on that centre
    /// — a full-width stack on a single display — resolves left. Without a
    /// display frame the side cannot be decided, and `.left` is the fallback.
    public static func side(
        for stackFrame: Rect,
        position: StripPosition,
        displayFrame: Rect?
    ) -> StripSide {
        switch position {
        case .left: return .left
        case .right: return .right
        case .auto:
            guard let displayFrame else { return .left }
            return stackFrame.midX > displayFrame.midX ? .right : .left
        }
    }

    /// Slid — never resized — until it lies inside `bounds` on both axes. When
    /// the strip is longer than the display on an axis it cannot fit at all, and
    /// the low edge wins: the overflow is left hanging off the high edge rather
    /// than the origin being pushed past the low edge, which would hide the
    /// strip's start and invert the two clamps against each other.
    public static func clamped(_ rect: Rect, to bounds: Rect) -> Rect {
        Rect(
            x: clampedOrigin(rect.minX, length: rect.width, low: bounds.minX, high: bounds.maxX),
            y: clampedOrigin(rect.minY, length: rect.height, low: bounds.minY, high: bounds.maxY),
            width: rect.width,
            height: rect.height
        )
    }

    private static func clampedOrigin(_ origin: Double, length: Double, low: Double, high: Double) -> Double {
        max(low, min(origin, high - length))
    }

    /// Offsets push the strip away from the corner it is anchored to: a
    /// positive `--offset-x` moves a left-anchored strip right and a
    /// right-anchored strip left, so the same value nudges either side inwards.
    /// A positive `--offset-y` always moves down, matching yabai's top-left
    /// origin and the strip's top anchoring.
    ///
    /// The result is clamped to the **display**, not to the stack frame: a
    /// narrow leaf carrying many icons has no placement that both fits and
    /// labels only its own frame, and a strip drawn off-display labels nothing
    /// at all. Overflowing a neighbouring stack is the lesser evil, so
    /// overflowing the stack frame stays legal.
    public static func layout(
        stackFrame: Rect,
        windowIDs: [Int],
        activeWindowID: Int? = nil,
        displayFrame: Rect?,
        configuration: Configuration
    ) -> StripLayout? {
        guard !windowIDs.isEmpty else { return nil }

        let stripSize = size(iconCount: windowIDs.count, configuration: configuration)
        let stripSide = side(for: stackFrame, position: configuration.position, displayFrame: displayFrame)
        let originX = switch stripSide {
        case .left: stackFrame.minX + configuration.offsetX
        case .right: stackFrame.maxX - stripSize.width - configuration.offsetX
        }
        let anchored = Rect(
            origin: Point(x: originX, y: stackFrame.minY + configuration.offsetY),
            size: stripSize
        )
        let frame = displayFrame.map { clamped(anchored, to: $0) } ?? anchored

        let step = configuration.iconSize + configuration.iconSpacing
        let icons = windowIDs.indices.map { index in
            Rect(
                x: frame.minX + configuration.padding + Double(index) * step,
                y: frame.minY + configuration.padding,
                width: configuration.iconSize,
                height: configuration.iconSize
            )
        }

        return StripLayout(
            side: stripSide,
            frame: frame,
            icons: icons,
            windowIDs: windowIDs,
            activeIndex: activeWindowID.flatMap { windowIDs.firstIndex(of: $0) }
        )
    }

    public static func layout(
        stack: Stack,
        displayFrame: Rect?,
        configuration: Configuration
    ) -> StripLayout? {
        layout(
            stackFrame: Rect(stack.frame),
            windowIDs: stack.members.map(\.id),
            activeWindowID: stack.activeWindowID,
            displayFrame: displayFrame,
            configuration: configuration
        )
    }

    /// The display frame comes from yabai's `--displays` query, not `NSScreen`,
    /// so the decision stays in yabai's coordinate space.
    public static func layout(
        stack: Stack,
        displays: [YabaiDisplay],
        configuration: Configuration
    ) -> StripLayout? {
        layout(
            stack: stack,
            displayFrame: displays.first { $0.index == stack.display }.map { Rect($0.frame) },
            configuration: configuration
        )
    }
}
