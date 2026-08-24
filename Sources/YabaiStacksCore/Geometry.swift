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

    /// Half-open on both axes, so two rects that touch never both contain the
    /// same point: a rect owns its low-coordinate edges (`minX`/`minY`) and not
    /// its high ones. Which edge that is on screen depends on the space — a
    /// yabai rect owns its top edge, the same rect converted to AppKit owns its
    /// bottom edge — so ownership does not survive conversion.
    public func contains(_ point: Point) -> Bool {
        point.x >= minX && point.x < maxX && point.y >= minY && point.y < maxY
    }

    public func offsetBy(dx: Double, dy: Double) -> Rect {
        Rect(x: x + dx, y: y + dy, width: width, height: height)
    }

    /// Positive insets shrink, negative ones grow. A shrink deeper than half an
    /// edge would flip that edge past the other, so the size floors at zero and
    /// the rect collapses onto its own centre instead.
    public func insetBy(dx: Double, dy: Double) -> Rect {
        Rect(
            x: x + min(dx, width / 2),
            y: y + min(dy, height / 2),
            width: max(0, width - dx * 2),
            height: max(0, height - dy * 2)
        )
    }
}

/// yabai reports frames in top-left-origin global coordinates; AppKit puts the
/// origin at the bottom-left of the primary display. Both systems share that
/// display's corner, so one flip converts every display, including ones at a
/// negative origin, and `x` is never touched.
///
/// The primary display's height is a parameter because Core must not import
/// AppKit and so cannot read `NSScreen` itself.
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

    /// A point carries no height to subtract, so this is not the rect formula
    /// with a zero-height rect substituted; converting a rect's origin is not
    /// the same as converting the rect.
    public static func appKitPoint(fromYabai point: Point, primaryDisplayHeight: Double) -> Point {
        Point(x: point.x, y: primaryDisplayHeight - point.y)
    }

    public static func yabaiPoint(fromAppKit point: Point, primaryDisplayHeight: Double) -> Point {
        appKitPoint(fromYabai: point, primaryDisplayHeight: primaryDisplayHeight)
    }

    public static let minimumDevicePixels = 1
    public static let maximumDevicePixels = 4096

    /// Backing-store pixels for a point size at a display scale. Lives here
    /// rather than in the icon adapter because it is pure arithmetic, and
    /// `Int(_:)` traps on a value that does not fit: every non-finite or absurd
    /// input has to be folded into range before the conversion, which is only
    /// checkable where there are tests.
    public static func devicePixels(pointSize: Double, scale: Double) -> Int {
        let pixels = (pointSize * scale).rounded()
        guard !pixels.isNaN else { return minimumDevicePixels }
        guard pixels > Double(minimumDevicePixels) else { return minimumDevicePixels }
        guard pixels < Double(maximumDevicePixels) else { return maximumDevicePixels }
        return Int(pixels)
    }
}
