public enum StripSide: String, Hashable, Sendable, CaseIterable {
    case left
    case right
}

/// One stack's icon strip. Every rect is in one coordinate space: yabai's as built,
/// AppKit's after `converted(toAppKitWithPrimaryDisplayHeight:)` flips the lot.
public struct StripLayout: Hashable, Sendable {
    public let side: StripSide
    public let frame: Rect
    public let icons: [Rect]
    public let windowIDs: [Int]
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

    /// Relative to `frame.origin`, which is what `NSEvent.locationInWindow` is relative to.
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
        let along = configuration.padding * 2
            + count * configuration.iconSize
            + max(0, count - 1) * configuration.iconSpacing
        let across = configuration.padding * 2 + configuration.iconSize
        return switch configuration.orientation {
        case .horizontal: Size(width: along, height: across)
        case .vertical: Size(width: across, height: along)
        }
    }

    /// `.auto` goes right only strictly past the display's centre, so a full-width
    /// stack resolves left; with no display frame the fallback is `.left`.
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

    /// Slid, never resized. A strip longer than the display cannot fit at all, and the
    /// low edge wins, so the overflow hangs off the high edge.
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

    public static func desktop(of screens: [Rect]) -> Rect? {
        guard let first = screens.first else { return nil }
        let bounds = screens.dropFirst().reduce(first) { union, screen in
            Rect(
                x: min(union.minX, screen.minX),
                y: min(union.minY, screen.minY),
                width: max(union.maxX, screen.maxX) - min(union.minX, screen.minX),
                height: max(union.maxY, screen.maxY) - min(union.minY, screen.minY)
            )
        }
        return bounds
    }

    public static let parkingMargin: Double = 8

    /// Where a strip waits while it is out of the way: past the nearer horizontal edge
    /// of the whole desktop, so it is off every display rather than merely off its own.
    public static func parked(_ rect: Rect, beyond desktop: Rect?, margin: Double = parkingMargin) -> Rect {
        guard let desktop else { return rect.offsetBy(dx: -rect.width * 2, dy: 0) }
        let exitsLeft = rect.midX <= desktop.midX
        let dx = exitsLeft ? desktop.minX - rect.maxX - margin : desktop.maxX - rect.minX + margin
        return rect.offsetBy(dx: dx, dy: 0)
    }

    /// A positive `--offset-x` nudges either side inwards. The frame is clamped to the
    /// display, not to the stack frame, so a narrow leaf's strip stays on screen.
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
        // The window buttons sit at the top-left, so only a left strip is inset.
        let originX = switch stripSide {
        case .left: stackFrame.minX + configuration.offsetX + configuration.titlebarInset
        case .right: stackFrame.maxX - stripSize.width - configuration.offsetX
        }
        let anchored = Rect(
            origin: Point(x: originX, y: stackFrame.minY + configuration.offsetY),
            size: stripSize
        )
        let frame = displayFrame.map { clamped(anchored, to: $0) } ?? anchored

        // Laid out top-left-origin, so index 0 stays the topmost icon after the flip.
        let step = configuration.iconSize + configuration.iconSpacing
        let icons = windowIDs.indices.map { index in
            let advance = Double(index) * step
            return switch configuration.orientation {
            case .horizontal:
                Rect(
                    x: frame.minX + configuration.padding + advance,
                    y: frame.minY + configuration.padding,
                    width: configuration.iconSize,
                    height: configuration.iconSize
                )
            case .vertical:
                Rect(
                    x: frame.minX + configuration.padding,
                    y: frame.minY + configuration.padding + advance,
                    width: configuration.iconSize,
                    height: configuration.iconSize
                )
            }
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

    /// The display frame comes from yabai, so the decision stays in yabai's space.
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
