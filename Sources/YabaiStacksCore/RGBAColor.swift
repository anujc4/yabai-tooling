public struct RGBAColor: Hashable, Sendable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8
    public let alpha: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 255) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public init(argb: UInt32) {
        self.init(
            red: UInt8((argb >> 16) & 0xff),
            green: UInt8((argb >> 8) & 0xff),
            blue: UInt8(argb & 0xff),
            alpha: UInt8((argb >> 24) & 0xff)
        )
    }

    public var argb: UInt32 {
        (UInt32(alpha) << 24) | (UInt32(red) << 16) | (UInt32(green) << 8) | UInt32(blue)
    }

    public var redFraction: Double { Double(red) / 255 }
    public var greenFraction: Double { Double(green) / 255 }
    public var blueFraction: Double { Double(blue) / 255 }
    public var alphaFraction: Double { Double(alpha) / 255 }

    public static func parse(_ text: String) -> RGBAColor? {
        let digits: Substring
        if text.hasPrefix("0x") || text.hasPrefix("0X") {
            digits = text.dropFirst(2)
        } else if text.hasPrefix("#") {
            digits = text.dropFirst()
        } else {
            return nil
        }

        guard digits.count == 6 || digits.count == 8,
              digits.allSatisfy(\.isHexDigit),
              let value = UInt32(digits, radix: 16)
        else { return nil }

        return RGBAColor(argb: digits.count == 8 ? value : value | 0xff00_0000)
    }
}
