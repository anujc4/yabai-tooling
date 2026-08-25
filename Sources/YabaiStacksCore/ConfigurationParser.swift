public enum ConfigurationError: Error, Hashable, Sendable {
    case unknownFlag(String)
    case unexpectedArgument(String)
    case missingValue(flag: String)
    case invalidValue(flag: String, value: String, expected: String)
    case outOfRange(flag: String, value: String, expected: String)
}

extension ConfigurationError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .unknownFlag(let flag):
            "unknown flag '\(flag)'"
        case .unexpectedArgument(let argument):
            "unexpected argument '\(argument)'"
        case .missingValue(let flag):
            "\(flag) requires a value"
        case .invalidValue(let flag, let value, let expected):
            "invalid value '\(value)' for \(flag): expected \(expected)"
        case .outOfRange(let flag, let value, let expected):
            "value '\(value)' out of range for \(flag): expected \(expected)"
        }
    }
}

/// The parser never prints and never exits, so every path is testable.
public enum CommandLineIntent: Hashable, Sendable {
    case help
    case version
    case run(Configuration)
}

public enum ConfigurationParser {
    public static let usage = """
    usage: yabai-stacks [options]

      --icon-size <pt>              default 28
      --icon-spacing <pt>           default 4
      --padding <pt>                default 5
      --corner-radius <pt>          default 6
      --active-color <0xAARRGGBB>   default 0xffd65d0e
      --background-color <0xAARRGGBB> default 0x801d2021
      --inactive-opacity <0..1>     default 0.45
      --border-width <pt>           default 0   ring around the active icon
      --position auto|left|right    default auto
      --orientation horizontal|vertical  default vertical
      --offset-x <pt>               default 0
      --offset-y <pt>               default 0
      --min-stack-size <n>          default 2
      --titlebar-inset <pt>         default 78
      --hide-on-hover               off by default; hides instead of clicking
      --help
      --version

    Colors accept 0xAARRGGBB, 0xRRGGBB and #RRGGBB.
    """

    /// Repeated flags are last-wins. `--help`/`--version` return before `validate()`,
    /// so `--inactive-opacity 9 --help` succeeds while `--bogus --help` still throws:
    /// parse errors fire in place, range errors only once the whole argv is read.
    public static func parse(_ arguments: [String]) throws -> CommandLineIntent {
        var configuration = Configuration()
        var index = arguments.startIndex

        func nextValue(for flag: String) throws -> String {
            guard index < arguments.endIndex else { throw ConfigurationError.missingValue(flag: flag) }
            let value = arguments[index]
            index += 1
            return value
        }

        while index < arguments.endIndex {
            let flag = arguments[index]
            index += 1

            switch flag {
            case "--help":
                return .help
            case "--version":
                return .version
            case "--icon-size":
                configuration.iconSize = try number(flag, try nextValue(for: flag))
            case "--icon-spacing":
                configuration.iconSpacing = try number(flag, try nextValue(for: flag))
            case "--padding":
                configuration.padding = try number(flag, try nextValue(for: flag))
            case "--corner-radius":
                configuration.cornerRadius = try number(flag, try nextValue(for: flag))
            case "--active-color":
                configuration.activeColor = try color(flag, try nextValue(for: flag))
            case "--background-color":
                configuration.backgroundColor = try color(flag, try nextValue(for: flag))
            case "--inactive-opacity":
                configuration.inactiveOpacity = try number(flag, try nextValue(for: flag))
            case "--border-width":
                configuration.borderWidth = try number(flag, try nextValue(for: flag))
            case "--position":
                configuration.position = try position(flag, try nextValue(for: flag))
            case "--orientation":
                configuration.orientation = try orientation(flag, try nextValue(for: flag))
            case "--offset-x":
                configuration.offsetX = try number(flag, try nextValue(for: flag))
            case "--offset-y":
                configuration.offsetY = try number(flag, try nextValue(for: flag))
            case "--titlebar-inset":
                configuration.titlebarInset = try number(flag, try nextValue(for: flag))
            case "--min-stack-size":
                configuration.minStackSize = try integer(flag, try nextValue(for: flag))
            case "--hide-on-hover":
                configuration.hideOnHover = true
            default:
                throw flag.hasPrefix("-")
                    ? ConfigurationError.unknownFlag(flag)
                    : ConfigurationError.unexpectedArgument(flag)
            }
        }

        try configuration.validate()
        return .run(configuration)
    }

    // `Double(_:)` accepts hex floats, so `--icon-size 0x18` would silently mean
    // 24pt in a CLI whose 0x prefix means a colour everywhere else.
    private static func number(_ flag: String, _ value: String) throws -> Double {
        guard !value.contains(where: { "xXpP".contains($0) }), let parsed = Double(value) else {
            throw ConfigurationError.invalidValue(flag: flag, value: value, expected: "a number")
        }
        return parsed
    }

    private static func integer(_ flag: String, _ value: String) throws -> Int {
        guard let parsed = Int(value) else {
            throw ConfigurationError.invalidValue(flag: flag, value: value, expected: "an integer")
        }
        return parsed
    }

    private static func color(_ flag: String, _ value: String) throws -> RGBAColor {
        guard let parsed = RGBAColor.parse(value) else {
            throw ConfigurationError.invalidValue(
                flag: flag, value: value, expected: "0xAARRGGBB, 0xRRGGBB or #RRGGBB"
            )
        }
        return parsed
    }

    private static func orientation(_ flag: String, _ value: String) throws -> StripOrientation {
        guard let orientation = StripOrientation(rawValue: value) else {
            throw ConfigurationError.outOfRange(
                flag: flag,
                value: value,
                expected: StripOrientation.allCases.map(\.rawValue).joined(separator: "|")
            )
        }
        return orientation
    }

    private static func position(_ flag: String, _ value: String) throws -> StripPosition {
        guard let parsed = StripPosition(rawValue: value) else {
            throw ConfigurationError.invalidValue(flag: flag, value: value, expected: "auto, left or right")
        }
        return parsed
    }
}
