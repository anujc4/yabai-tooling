public enum StripPosition: String, Hashable, Sendable, CaseIterable {
    case auto
    case left
    case right
}

/// Icons run left-to-right or top-to-bottom. Vertical keeps a wide stack's
/// strip out of the window's own titlebar area.
public enum StripOrientation: String, Hashable, Sendable, CaseIterable {
    case horizontal
    case vertical
}

public struct Configuration: Hashable, Sendable {
    public var iconSize: Double
    public var iconSpacing: Double
    public var padding: Double
    public var cornerRadius: Double
    public var activeColor: RGBAColor
    public var backgroundColor: RGBAColor
    public var inactiveOpacity: Double
    public var borderWidth: Double
    public var position: StripPosition
    public var orientation: StripOrientation
    public var offsetX: Double
    public var offsetY: Double
    public var minStackSize: Int
    public var titlebarInset: Double

    /// The strip gets out of the way while the cursor is over it, and registers
    /// no click actions at all: hiding is the whole interaction, so an icon
    /// that could be clicked would only ever be clicked by accident.
    public var hideOnHover: Bool

    public init(
        iconSize: Double = 28,
        iconSpacing: Double = 4,
        padding: Double = 5,
        cornerRadius: Double = 6,
        activeColor: RGBAColor = RGBAColor(argb: 0xffd6_5d0e),
        backgroundColor: RGBAColor = RGBAColor(argb: 0x801d_2021),
        inactiveOpacity: Double = 0.45,
        borderWidth: Double = 0,
        position: StripPosition = .auto,
        orientation: StripOrientation = .vertical,
        offsetX: Double = 0,
        offsetY: Double = 0,
        minStackSize: Int = 2,
        titlebarInset: Double = 78,
        hideOnHover: Bool = false
    ) {
        self.iconSize = iconSize
        self.iconSpacing = iconSpacing
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.activeColor = activeColor
        self.backgroundColor = backgroundColor
        self.inactiveOpacity = inactiveOpacity
        self.borderWidth = borderWidth
        self.position = position
        self.orientation = orientation
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.minStackSize = minStackSize
        self.titlebarInset = titlebarInset
        self.hideOnHover = hideOnHover
    }

    /// Only `--icon-size` must be strictly positive; a zero gap, corner radius
    /// or border is meaningful, and offsets are signed. Every bound is also a
    /// magnitude: a finite but absurd value passes sign checks and then produces
    /// garbage geometry downstream.
    public static let maximumLength: Double = 512
    public static let minimumIconSize: Double = 1
    public static let maximumOffset: Double = 100_000

    public func validate() throws {
        try Self.require(iconSize, in: Self.minimumIconSize...Self.maximumLength, flag: "--icon-size")
        try Self.require(iconSpacing, in: 0...Self.maximumLength, flag: "--icon-spacing")
        try Self.require(padding, in: 0...Self.maximumLength, flag: "--padding")
        try Self.require(cornerRadius, in: 0...Self.maximumLength, flag: "--corner-radius")
        try Self.require(borderWidth, in: 0...Self.maximumLength, flag: "--border-width")
        try Self.require(titlebarInset, in: 0...Self.maximumOffset, flag: "--titlebar-inset")
        try Self.require(offsetX, in: -Self.maximumOffset...Self.maximumOffset, flag: "--offset-x")
        try Self.require(offsetY, in: -Self.maximumOffset...Self.maximumOffset, flag: "--offset-y")

        guard inactiveOpacity.isFinite, inactiveOpacity >= 0, inactiveOpacity <= 1 else {
            throw ConfigurationError.outOfRange(
                flag: "--inactive-opacity", value: String(inactiveOpacity), expected: "a number in 0...1"
            )
        }
        guard minStackSize >= 1 else {
            throw ConfigurationError.outOfRange(
                flag: "--min-stack-size", value: String(minStackSize), expected: "an integer >= 1"
            )
        }
    }

    // The isFinite guard is what rejects the inf/nan that `Double("...")` takes;
    // a NaN would also fail `contains`, but silently.
    private static func require(_ value: Double, in range: ClosedRange<Double>, flag: String) throws {
        guard value.isFinite, range.contains(value) else {
            throw ConfigurationError.outOfRange(
                flag: flag,
                value: String(value),
                expected: "a finite number in \(range.lowerBound)...\(range.upperBound)"
            )
        }
    }
}
