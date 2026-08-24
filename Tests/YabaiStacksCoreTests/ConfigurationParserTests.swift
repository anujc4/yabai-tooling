import Foundation
import Testing
@testable import YabaiStacksCore

@Suite("CLI configuration parsing")
struct ConfigurationParserTests {
    enum Failure: Error { case notARunIntent(CommandLineIntent) }

    private func configuration(_ arguments: [String]) throws -> Configuration {
        let intent = try ConfigurationParser.parse(arguments)
        guard case .run(let configuration) = intent else { throw Failure.notARunIntent(intent) }
        return configuration
    }

    // MARK: - Defaults

    @Test("empty argv yields every documented default")
    func defaults() throws {
        let configuration = try self.configuration([])

        #expect(configuration.iconSize == 28)
        #expect(configuration.iconSpacing == 4)
        #expect(configuration.padding == 5)
        #expect(configuration.cornerRadius == 6)
        #expect(configuration.activeColor.argb == 0xffd6_5d0e)
        #expect(configuration.backgroundColor.argb == 0x801d_2021)
        #expect(configuration.inactiveOpacity == 0.45)
        #expect(configuration.borderWidth == 0)
        #expect(configuration.position == .auto)
        #expect(configuration.orientation == .vertical)
        #expect(configuration.offsetX == 0)
        #expect(configuration.offsetY == 0)
        #expect(configuration.minStackSize == 2)
        #expect(configuration.titlebarInset == 78)
        #expect(configuration.hideOnHover == false)
        #expect(configuration == Configuration())
    }

    // MARK: - Individual flags

    @Test("each numeric flag lands on its own property")
    func numericFlags() throws {
        #expect(try configuration(["--icon-size", "24"]).iconSize == 24)
        #expect(try configuration(["--icon-spacing", "7.5"]).iconSpacing == 7.5)
        #expect(try configuration(["--padding", "0"]).padding == 0)
        #expect(try configuration(["--corner-radius", "12"]).cornerRadius == 12)
        #expect(try configuration(["--inactive-opacity", "0.8"]).inactiveOpacity == 0.8)
        #expect(try configuration(["--border-width", "1.5"]).borderWidth == 1.5)
        #expect(try configuration(["--offset-x", "-12"]).offsetX == -12)
        #expect(try configuration(["--offset-y", "3.25"]).offsetY == 3.25)
        #expect(try configuration(["--min-stack-size", "4"]).minStackSize == 4)
    }

    @Test("setting one flag leaves the rest at their defaults")
    func flagsAreIndependent() throws {
        let configuration = try self.configuration(["--icon-size", "40"])
        #expect(configuration == Configuration(iconSize: 40))
    }

    @Test("every position is accepted")
    func positions() throws {
        #expect(try configuration(["--position", "auto"]).position == .auto)
        #expect(try configuration(["--position", "left"]).position == .left)
        #expect(try configuration(["--position", "right"]).position == .right)
        #expect(StripPosition.allCases.count == 3)
    }

    @Test("all flags together")
    func everyFlagAtOnce() throws {
        let configuration = try self.configuration([
            "--icon-size", "20",
            "--icon-spacing", "6",
            "--padding", "8",
            "--corner-radius", "10",
            "--active-color", "0xff00ff00",
            "--background-color", "#101112",
            "--inactive-opacity", "0",
            "--border-width", "2",
            "--position", "right",
            "--offset-x", "-4",
            "--offset-y", "4",
            "--min-stack-size", "3",
            "--titlebar-inset", "0",
            "--hide-on-hover",
        ])

        #expect(configuration == Configuration(
            iconSize: 20,
            iconSpacing: 6,
            padding: 8,
            cornerRadius: 10,
            activeColor: RGBAColor(argb: 0xff00_ff00),
            backgroundColor: RGBAColor(argb: 0xff10_1112),
            inactiveOpacity: 0,
            borderWidth: 2,
            position: .right,
            offsetX: -4,
            offsetY: 4,
            minStackSize: 3,
            titlebarInset: 0,
            hideOnHover: true
        ))
    }

    /// A presence flag: it takes no value, so the token after it is the next
    /// flag and must not be swallowed as this one's argument.
    @Test("--hide-on-hover is off by default and takes no value")
    func hideOnHoverFlag() throws {
        #expect(try configuration([]).hideOnHover == false)
        #expect(try configuration(["--hide-on-hover"]).hideOnHover == true)
        #expect(try configuration(["--hide-on-hover"]) == Configuration(hideOnHover: true))

        // The following flag survives in both orders, which is what proves the
        // value was never consumed.
        #expect(try configuration(["--hide-on-hover", "--icon-size", "40"])
            == Configuration(iconSize: 40, hideOnHover: true))
        #expect(try configuration(["--icon-size", "40", "--hide-on-hover"])
            == Configuration(iconSize: 40, hideOnHover: true))

        // Presence, not a toggle: repeating it does not turn it back off.
        #expect(try configuration(["--hide-on-hover", "--hide-on-hover"]).hideOnHover == true)
    }

    @Test("--hide-on-hover does not swallow a positional or a bad flag after it")
    func hideOnHoverDoesNotHideErrors() throws {
        #expect(throws: ConfigurationError.unknownFlag("--bogus")) {
            try ConfigurationParser.parse(["--hide-on-hover", "--bogus"])
        }
        #expect(throws: ConfigurationError.unexpectedArgument("true")) {
            try ConfigurationParser.parse(["--hide-on-hover", "true"])
        }
        #expect(try ConfigurationParser.parse(["--hide-on-hover", "--help"]) == .help)
    }

    // MARK: - Intents

    @Test("--help and --version return an intent instead of exiting")
    func intents() throws {
        #expect(try ConfigurationParser.parse(["--help"]) == .help)
        #expect(try ConfigurationParser.parse(["--version"]) == .version)
        #expect(try ConfigurationParser.parse(["--icon-size", "20", "--help"]) == .help)
        #expect(try ConfigurationParser.parse(["--icon-size", "20", "--version"]) == .version)
        #expect(try ConfigurationParser.parse([]) == .run(Configuration()))
    }

    @Test("--help short-circuits later flags but not an earlier bad one")
    func helpShortCircuits() throws {
        #expect(try ConfigurationParser.parse(["--help", "--bogus"]) == .help)
        #expect(try ConfigurationParser.parse(["--help", "--icon-size"]) == .help)
        #expect(throws: ConfigurationError.unknownFlag("--bogus")) {
            try ConfigurationParser.parse(["--bogus", "--help"])
        }
    }

    @Test("the first of --help and --version wins")
    func intentOrder() throws {
        #expect(try ConfigurationParser.parse(["--help", "--version"]) == .help)
        #expect(try ConfigurationParser.parse(["--version", "--help"]) == .version)
    }

    // MARK: - Colours

    @Test("all three colour formats parse")
    func colorFormats() throws {
        #expect(try configuration(["--active-color", "0xffd65d0e"]).activeColor == RGBAColor(argb: 0xffd6_5d0e))
        #expect(try configuration(["--active-color", "0xd65d0e"]).activeColor == RGBAColor(argb: 0xffd6_5d0e))
        #expect(try configuration(["--active-color", "#d65d0e"]).activeColor == RGBAColor(argb: 0xffd6_5d0e))
        #expect(try configuration(["--active-color", "0XD65D0E"]).activeColor == RGBAColor(argb: 0xffd6_5d0e))
        #expect(try configuration(["--active-color", "#AABBCCDD"]).activeColor == RGBAColor(argb: 0xaabb_ccdd))
    }

    @Test("the six-digit forms imply an opaque alpha, the eight-digit form keeps it")
    func alphaHandling() throws {
        #expect(try configuration(["--background-color", "#000000"]).backgroundColor.alpha == 255)
        #expect(try configuration(["--background-color", "0x00000000"]).backgroundColor.alpha == 0)
        #expect(try configuration(["--background-color", "0x801d2021"]).backgroundColor.alpha == 0x80)
    }

    @Test("colour components split correctly")
    func colorComponents() {
        let color = RGBAColor(argb: 0x8012_3456)
        #expect(color.alpha == 0x80)
        #expect(color.red == 0x12)
        #expect(color.green == 0x34)
        #expect(color.blue == 0x56)
        #expect(color.argb == 0x8012_3456)
        #expect(RGBAColor(red: 0x12, green: 0x34, blue: 0x56).alpha == 255)
        #expect(RGBAColor(argb: 0xffff_ffff).redFraction == 1)
        #expect(RGBAColor(argb: 0x0000_0000).alphaFraction == 0)
        #expect(abs(RGBAColor(argb: 0x8000_0000).alphaFraction - 128.0 / 255.0) < 1e-12)
    }

    @Test("malformed colours are rejected")
    func invalidColors() {
        for value in ["0xfff", "#12345", "0xgg0000", "d65d0e", "", "0x", "#", "0x1234567890", "0x d65d0e"] {
            #expect(throws: ConfigurationError.self, "accepted '\(value)'") {
                try ConfigurationParser.parse(["--active-color", value])
            }
            #expect(RGBAColor.parse(value) == nil, "accepted '\(value)'")
        }
    }

    // MARK: - Malformed argv

    @Test("an unknown flag is an error, not a silent default")
    func unknownFlag() {
        #expect(throws: ConfigurationError.unknownFlag("--icon-sixe")) {
            try ConfigurationParser.parse(["--icon-sixe", "20"])
        }
        #expect(throws: ConfigurationError.unknownFlag("-x")) {
            try ConfigurationParser.parse(["--icon-size", "20", "-x"])
        }
        #expect(throws: ConfigurationError.unexpectedArgument("stack")) {
            try ConfigurationParser.parse(["stack"])
        }
    }

    @Test("a flag with no value is an error")
    func missingValue() {
        for flag in [
            "--icon-size", "--icon-spacing", "--padding", "--corner-radius",
            "--active-color", "--background-color", "--inactive-opacity",
            "--border-width", "--position", "--offset-x", "--offset-y", "--min-stack-size",
        ] {
            #expect(throws: ConfigurationError.missingValue(flag: flag)) {
                try ConfigurationParser.parse([flag])
            }
        }
    }

    @Test("unparseable numbers name the flag and the value")
    func unparseableNumbers() {
        #expect(throws: ConfigurationError.invalidValue(flag: "--icon-size", value: "big", expected: "a number")) {
            try ConfigurationParser.parse(["--icon-size", "big"])
        }
        #expect(throws: ConfigurationError.invalidValue(flag: "--padding", value: "5px", expected: "a number")) {
            try ConfigurationParser.parse(["--padding", "5px"])
        }
        #expect(throws: ConfigurationError.invalidValue(flag: "--min-stack-size", value: "2.5", expected: "an integer")) {
            try ConfigurationParser.parse(["--min-stack-size", "2.5"])
        }
        #expect(throws: ConfigurationError.invalidValue(flag: "--position", value: "top", expected: "auto, left or right")) {
            try ConfigurationParser.parse(["--position", "top"])
        }
        #expect(throws: ConfigurationError.self) { try ConfigurationParser.parse(["--icon-size", ""]) }
    }

    @Test("a following flag consumed as a value fails loudly")
    func flagAsValue() {
        #expect(throws: ConfigurationError.invalidValue(flag: "--icon-size", value: "--padding", expected: "a number")) {
            try ConfigurationParser.parse(["--icon-size", "--padding", "5"])
        }
    }

    // MARK: - Validation boundaries

    @Test("--icon-size is bounded at both ends")
    func iconSizeRange() throws {
        #expect(try configuration(["--icon-size", "1"]).iconSize == 1)
        #expect(try configuration(["--icon-size", "512"]).iconSize == 512)
        for value in ["0", "0.999", "5e-324", "-0.001", "-18", "512.001", "1.797e308", "inf", "nan", "-inf"] {
            #expect(throws: ConfigurationError.self, "accepted '\(value)'") {
                try ConfigurationParser.parse(["--icon-size", value])
            }
        }
    }

    @Test("numbers are decimal: hex and hex-float notation is refused")
    func hexNumbersAreRefused() {
        for value in ["0x10", "0X18", "0x1p4", "1P4"] {
            #expect(throws: ConfigurationError.invalidValue(flag: "--icon-size", value: value, expected: "a number")) {
                try ConfigurationParser.parse(["--icon-size", value])
            }
        }
        #expect(throws: ConfigurationError.self) { try ConfigurationParser.parse(["--min-stack-size", "0x10"]) }
    }

    @Test("conventional decimal spellings still parse")
    func conventionalNumberSpellings() throws {
        #expect(try configuration(["--icon-size", "+18"]).iconSize == 18)
        #expect(try configuration(["--padding", ".5"]).padding == 0.5)
        #expect(try configuration(["--padding", "5."]).padding == 5)
        #expect(try configuration(["--icon-spacing", "1e1"]).iconSpacing == 10)
    }

    private func zeroed(_ flag: String) -> Configuration {
        var configuration = Configuration()
        switch flag {
        case "--icon-spacing": configuration.iconSpacing = 0
        case "--padding": configuration.padding = 0
        case "--corner-radius": configuration.cornerRadius = 0
        default: configuration.borderWidth = 0
        }
        return configuration
    }

    @Test("spacing, padding, radius and border run 0...512")
    func nonNegativeRanges() throws {
        for flag in ["--icon-spacing", "--padding", "--corner-radius", "--border-width"] {
            #expect(try ConfigurationParser.parse([flag, "0"]) == .run(zeroed(flag)))
            #expect(throws: Never.self, "\(flag) refused 512") { try ConfigurationParser.parse([flag, "512"]) }
            for value in ["-0.001", "512.001", "1e6", "inf", "nan"] {
                #expect(throws: ConfigurationError.self, "\(flag) accepted \(value)") {
                    try ConfigurationParser.parse([flag, value])
                }
            }
        }
    }

    @Test("offsets are signed and bounded at +/-100000")
    func offsetRanges() throws {
        #expect(try configuration(["--offset-x", "-1000"]).offsetX == -1000)
        #expect(try configuration(["--offset-y", "-1000"]).offsetY == -1000)
        #expect(try configuration(["--offset-x", "100000"]).offsetX == 100_000)
        #expect(try configuration(["--offset-y", "-100000"]).offsetY == -100_000)
        for flag in ["--offset-x", "--offset-y"] {
            for value in ["100000.001", "-100000.001", "inf", "-inf", "nan"] {
                #expect(throws: ConfigurationError.self, "\(flag) accepted \(value)") {
                    try ConfigurationParser.parse([flag, value])
                }
            }
        }
    }

    @Test("--inactive-opacity is inclusive 0...1")
    func opacityRange() throws {
        #expect(try configuration(["--inactive-opacity", "0"]).inactiveOpacity == 0)
        #expect(try configuration(["--inactive-opacity", "1"]).inactiveOpacity == 1)
        #expect(try configuration(["--inactive-opacity", "0.999"]).inactiveOpacity == 0.999)

        for value in ["-0.001", "1.001", "2", "-1", "nan", "inf"] {
            #expect(
                throws: ConfigurationError.outOfRange(
                    flag: "--inactive-opacity",
                    value: String(Double(value) ?? .nan),
                    expected: "a number in 0...1"
                )
            ) {
                try ConfigurationParser.parse(["--inactive-opacity", value])
            }
        }
    }

    @Test("--min-stack-size must be at least 1")
    func minStackSizeRange() throws {
        #expect(try configuration(["--min-stack-size", "1"]).minStackSize == 1)
        #expect(try configuration(["--min-stack-size", "99"]).minStackSize == 99)
        #expect(
            throws: ConfigurationError.outOfRange(
                flag: "--min-stack-size", value: "0", expected: "an integer >= 1"
            )
        ) {
            try ConfigurationParser.parse(["--min-stack-size", "0"])
        }
        #expect(throws: ConfigurationError.self) { try ConfigurationParser.parse(["--min-stack-size", "-3"]) }
    }

    @Test("validation runs on the whole configuration, not just the last flag")
    func validationIsWholeConfiguration() {
        #expect(throws: ConfigurationError.self) {
            try ConfigurationParser.parse(["--icon-size", "-1", "--padding", "4"])
        }
        #expect(throws: ConfigurationError.self) { try Configuration(iconSize: 0).validate() }
        #expect(throws: Never.self) { try Configuration().validate() }
    }

    // MARK: - Repetition

    @Test("a repeated flag is last-wins")
    func repeatedFlagsAreLastWins() throws {
        #expect(try configuration(["--icon-size", "20", "--icon-size", "30"]).iconSize == 30)
        #expect(try configuration(["--position", "left", "--position", "right"]).position == .right)
        #expect(try configuration(["--active-color", "#000000", "--active-color", "#ffffff"]).activeColor
            == RGBAColor(argb: 0xffff_ffff))
        // Last-wins is applied before validation, so an invalid earlier value
        // that is later overwritten is still accepted.
        #expect(try configuration(["--icon-size", "-1", "--icon-size", "10"]).iconSize == 10)
        #expect(throws: ConfigurationError.self) {
            try ConfigurationParser.parse(["--icon-size", "10", "--icon-size", "-1"])
        }
    }

    // MARK: - Diagnostics

    @Test("error descriptions name the flag and the received value")
    func errorDescriptions() {
        #expect(String(describing: ConfigurationError.unknownFlag("--icon-sixe")).contains("--icon-sixe"))
        #expect(String(describing: ConfigurationError.missingValue(flag: "--padding")).contains("--padding"))

        let invalid = String(describing: ConfigurationError.invalidValue(
            flag: "--active-color", value: "nope", expected: "0xAARRGGBB, 0xRRGGBB or #RRGGBB"
        ))
        #expect(invalid.contains("--active-color"))
        #expect(invalid.contains("nope"))

        let range = String(describing: ConfigurationError.outOfRange(
            flag: "--inactive-opacity", value: "2.0", expected: "a number in 0...1"
        ))
        #expect(range.contains("--inactive-opacity"))
        #expect(range.contains("2.0"))
        #expect(String(describing: ConfigurationError.unexpectedArgument("stack")).contains("stack"))
    }

    @Test("the usage text lists every flag")
    func usageMentionsEveryFlag() {
        let usage = ConfigurationParser.usage
        for flag in [
            "--icon-size", "--icon-spacing", "--padding", "--corner-radius",
            "--active-color", "--background-color", "--inactive-opacity",
            "--border-width", "--position", "--offset-x", "--offset-y",
            "--min-stack-size", "--titlebar-inset", "--hide-on-hover", "--help", "--version",
        ] {
            #expect(usage.contains(flag), "usage omits \(flag)")
        }
    }
}
