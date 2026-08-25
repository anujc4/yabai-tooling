public struct Point: Hashable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct Size: Hashable, Sendable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct Rect: Hashable, Sendable {
    public let origin: Point
    public let size: Size

    public init(origin: Point, size: Size) {
        self.origin = origin
        self.size = size
    }

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.init(origin: Point(x: x, y: y), size: Size(width: width, height: height))
    }

    public init(_ frame: YabaiFrame) {
        self.init(x: frame.x, y: frame.y, width: frame.w, height: frame.h)
    }

    public var x: Double { origin.x }
    public var y: Double { origin.y }
    public var width: Double { size.width }
    public var height: Double { size.height }

    public var minX: Double { origin.x }
    public var minY: Double { origin.y }
    public var maxX: Double { origin.x + size.width }
    public var maxY: Double { origin.y + size.height }
    public var midX: Double { origin.x + size.width / 2 }
    public var midY: Double { origin.y + size.height / 2 }

    public var yabaiFrame: YabaiFrame {
        YabaiFrame(x: x, y: y, w: width, h: height)
    }

    /// Half-open on both axes, so two touching rects never both contain a point:
    /// a click on a boundary resolves to exactly one icon.
    public func contains(_ point: Point) -> Bool {
        point.x >= minX && point.x < maxX && point.y >= minY && point.y < maxY
    }

    public func offsetBy(dx: Double, dy: Double) -> Rect {
        Rect(x: x + dx, y: y + dy, width: width, height: height)
    }

    /// Negative insets grow. An over-deep shrink collapses the rect onto its centre.
    public func insetBy(dx: Double, dy: Double) -> Rect {
        Rect(
            x: x + min(dx, width / 2),
            y: y + min(dy, height / 2),
            width: max(0, width - dx * 2),
            height: max(0, height - dy * 2)
        )
    }
}

/// yabai reports frames top-left-origin, AppKit bottom-left. Both share the
/// primary display's corner, so one flip converts every display and `x` never moves.
public enum Geometry {
    public static func appKitRect(fromYabai rect: Rect, primaryDisplayHeight: Double) -> Rect {
        Rect(x: rect.x, y: primaryDisplayHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    public static func appKitRect(fromYabai frame: YabaiFrame, primaryDisplayHeight: Double) -> Rect {
        appKitRect(fromYabai: Rect(frame), primaryDisplayHeight: primaryDisplayHeight)
    }

    // The flip is an involution, so the inverse is the same computation.
    public static func yabaiRect(fromAppKit rect: Rect, primaryDisplayHeight: Double) -> Rect {
        appKitRect(fromYabai: rect, primaryDisplayHeight: primaryDisplayHeight)
    }

    /// Converting a rect's origin is not converting the rect: the origin lands on the
    /// converted rect's top edge, not its bottom.
    public static func appKitPoint(fromYabai point: Point, primaryDisplayHeight: Double) -> Point {
        Point(x: point.x, y: primaryDisplayHeight - point.y)
    }

    public static func yabaiPoint(fromAppKit point: Point, primaryDisplayHeight: Double) -> Point {
        appKitPoint(fromYabai: point, primaryDisplayHeight: primaryDisplayHeight)
    }

    public static let minimumDevicePixels = 1
    public static let maximumDevicePixels = 4096

    /// `Int(_:)` traps on a value that does not fit, so every input is folded into range.
    public static func devicePixels(pointSize: Double, scale: Double) -> Int {
        let pixels = (pointSize * scale).rounded()
        guard !pixels.isNaN else { return minimumDevicePixels }
        guard pixels > Double(minimumDevicePixels) else { return minimumDevicePixels }
        guard pixels < Double(maximumDevicePixels) else { return maximumDevicePixels }
        return Int(pixels)
    }
}
