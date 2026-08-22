import Foundation
import Testing
@testable import YabaiStacksCore

/// The fixtures prove the real-world shape, but they cannot catch a swap
/// between two keys that happen to share a value — `is-minimized`, `is-sticky`
/// and `is-hidden` are false for all 13 captured windows. These synthetic
/// objects give every key a value nothing else has, so each mapping is pinned
/// on its own.
@Suite("CodingKey mapping")
struct CodingKeyMappingTests {
    static let booleanKeys = [
        "root-window", "has-focus", "is-visible",
        "is-floating", "is-minimized", "is-hidden", "is-sticky",
    ]

    static func windowJSON(trueKey: String?) -> Data {
        func flag(_ key: String) -> String { key == trueKey ? "true" : "false" }
        return Data("""
        {
          "id": 11, "pid": 22, "app": "SyntheticApp", "title": "SyntheticTitle",
          "frame": { "x": 1.5, "y": 2.25, "w": 3.125, "h": 4.0625 },
          "role": "AXWindow", "subrole": "AXSyntheticRole",
          "display": 33, "space": 44, "level": 55, "stack-index": 66,
          "root-window": \(flag("root-window")),
          "has-focus": \(flag("has-focus")),
          "is-visible": \(flag("is-visible")),
          "is-floating": \(flag("is-floating")),
          "is-minimized": \(flag("is-minimized")),
          "is-hidden": \(flag("is-hidden")),
          "is-sticky": \(flag("is-sticky"))
        }
        """.utf8)
    }

    static func flags(of window: YabaiWindow) -> [String: Bool] {
        [
            "root-window": window.isRootWindow,
            "has-focus": window.hasFocus,
            "is-visible": window.isVisible,
            "is-floating": window.isFloating,
            "is-minimized": window.isMinimized,
            "is-hidden": window.isHidden,
            "is-sticky": window.isSticky,
        ]
    }

    @Test("each window boolean key drives exactly one property", arguments: CodingKeyMappingTests.booleanKeys)
    func windowBooleanKeys(key: String) throws {
        let window = try JSONDecoder().decode(YabaiWindow.self, from: Self.windowJSON(trueKey: key))
        let flags = Self.flags(of: window)

        #expect(flags[key] == true, "\(key) did not set its own property")
        for (other, value) in flags where other != key {
            #expect(value == false, "\(key) also set \(other)")
        }
    }

    @Test("every window boolean is false when no key is set")
    func windowBooleansDefaultApart() throws {
        let window = try JSONDecoder().decode(YabaiWindow.self, from: Self.windowJSON(trueKey: nil))
        #expect(Self.flags(of: window).values.allSatisfy { $0 == false })
    }

    @Test("window scalar keys land on distinct properties")
    func windowScalarKeys() throws {
        let window = try JSONDecoder().decode(YabaiWindow.self, from: Self.windowJSON(trueKey: nil))

        #expect(window.id == 11)
        #expect(window.pid == 22)
        #expect(window.display == 33)
        #expect(window.space == 44)
        #expect(window.level == 55)
        #expect(window.stackIndex == 66)
        #expect(window.app == "SyntheticApp")
        #expect(window.title == "SyntheticTitle")
        #expect(window.subrole == "AXSyntheticRole")
        #expect(window.frame == YabaiFrame(x: 1.5, y: 2.25, w: 3.125, h: 4.0625))
    }

    @Test("space booleans do not share a mapping", arguments: [true, false])
    func spaceBooleanKeys(focused: Bool) throws {
        let json = Data("""
        {
          "uuid": "SYNTHETIC-UUID", "index": 7, "label": "", "type": "bsp", "display": 9,
          "has-focus": \(focused), "is-visible": \(!focused)
        }
        """.utf8)
        let space = try JSONDecoder().decode(YabaiSpace.self, from: json)

        #expect(space.hasFocus == focused)
        #expect(space.isVisible == !focused)
        #expect(space.uuid == "SYNTHETIC-UUID")
        #expect(space.index == 7)
        #expect(space.display == 9)
        #expect(space.type == "bsp")
    }

    @Test("display keys land on distinct properties")
    func displayKeys() throws {
        let json = Data("""
        { "id": 1, "uuid": "DISPLAY-UUID", "index": 4,
          "frame": { "x": 5.5, "y": 6.5, "w": 7.5, "h": 8.5 } }
        """.utf8)
        let display = try JSONDecoder().decode(YabaiDisplay.self, from: json)

        #expect(display.index == 4)
        #expect(display.uuid == "DISPLAY-UUID")
        #expect(display.frame == YabaiFrame(x: 5.5, y: 6.5, w: 7.5, h: 8.5))
    }
}
