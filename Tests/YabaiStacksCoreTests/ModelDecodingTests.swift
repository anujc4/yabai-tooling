import Foundation
import Testing
@testable import YabaiStacksCore

@Suite("Model decoding against captured yabai v7.1.24 output")
struct ModelDecodingTests {
    private let decoder = JSONDecoder()

    @Test("every fixture decodes")
    func allFixturesDecode() throws {
        #expect(try decoder.decode([YabaiWindow].self, from: Fixture.windowsAll.data()).count == 13)
        #expect(try decoder.decode([YabaiWindow].self, from: Fixture.windowsStackVisible.data()).count == 4)
        #expect(try decoder.decode([YabaiSpace].self, from: Fixture.spaces.data()).count == 10)
        #expect(try decoder.decode([YabaiDisplay].self, from: Fixture.displays.data()).count == 1)
    }

    @Test("windows-all: Alacritty 577003 is the single focused window")
    func focusedWindow() throws {
        let windows = try decoder.decode([YabaiWindow].self, from: Fixture.windowsAll.data())
        let focused = windows.filter(\.hasFocus)

        #expect(focused.count == 1)
        #expect(focused.first?.id == 577003)
        #expect(focused.first?.app == "Alacritty")
        #expect(focused.first?.title == "Alacritty")
        #expect(focused.first?.space == 4)
        #expect(focused.first?.display == 1)
        #expect(focused.first?.pid == 95878)
        #expect(focused.first?.stackIndex == 0)
        #expect(focused.first?.isVisible == false)
    }

    @Test("windows-all: the space-2 Code stack is 4 windows with contiguous 1-based indices")
    func codeStack() throws {
        let windows = try decoder.decode([YabaiWindow].self, from: Fixture.windowsAll.data())
        let stacked = windows.filter { $0.space == 2 && $0.stackIndex >= 1 }

        #expect(stacked.count == 4)
        #expect(stacked.allSatisfy { $0.app == "Code" })
        #expect(stacked.map(\.stackIndex).sorted() == [1, 2, 3, 4])
        #expect(Set(stacked.map(\.frame)).count == 1)
        #expect(stacked.first?.frame == YabaiFrame(x: 10, y: 50, w: 1780, h: 1079))

        let byIndex = stacked.sorted { $0.stackIndex < $1.stackIndex }
        #expect(byIndex.map(\.id) == [732842, 783797, 783800, 783803])
        #expect(byIndex.first?.title == "Untitled-1 — homelab")
    }

    @Test("windows-all: unstacked windows report stack-index 0")
    func unstackedWindows() throws {
        let windows = try decoder.decode([YabaiWindow].self, from: Fixture.windowsAll.data())
        let unstacked = windows.filter { $0.stackIndex == 0 }

        #expect(unstacked.count == 9)
        #expect(unstacked.allSatisfy { $0.space != 2 })
    }

    @Test("windows-all: kebab-case boolean keys map onto the right properties")
    func booleanKeys() throws {
        let windows = try decoder.decode([YabaiWindow].self, from: Fixture.windowsAll.data())
        let floatingVLC = try #require(windows.first { $0.id == 783535 })

        #expect(floatingVLC.app == "VLC")
        #expect(floatingVLC.title == "Fullscreen Controls")
        #expect(floatingVLC.isFloating)
        #expect(floatingVLC.isVisible)
        #expect(floatingVLC.isRootWindow)
        #expect(!floatingVLC.isMinimized)
        #expect(!floatingVLC.isHidden)
        #expect(!floatingVLC.isSticky)
        #expect(floatingVLC.level == 8)
        #expect(floatingVLC.subrole == "AXDialog")
        #expect(floatingVLC.frame == YabaiFrame(x: 658, y: 936, w: 483, h: 84))

        let hiddenVLC = try #require(windows.first { $0.id == 783542 })
        #expect(!hiddenVLC.isVisible)
        #expect(!hiddenVLC.isFloating)
    }

    @Test("windows-stack-visible: yabai returns stack members in descending order, all visible")
    func stackOrderingAndVisibility() throws {
        let windows = try decoder.decode([YabaiWindow].self, from: Fixture.windowsStackVisible.data())

        // SPEC 3: the wire order is descending, so ascending sorting is mandatory.
        #expect(windows.map(\.stackIndex) == [4, 3, 2, 1])
        // SPEC 4: is-visible is true for every member, so it cannot identify the top.
        #expect(windows.allSatisfy { $0.isVisible })
        #expect(windows.filter { $0.hasFocus }.map { $0.id } == [783803])
        #expect(Set(windows.map(\.frame)).count == 1)
        #expect(Set(windows.map(\.space)) == [2])
        #expect(Set(windows.map(\.pid)) == [52813])
    }

    @Test("spaces decode with kebab-case keys")
    func spaces() throws {
        let spaces = try decoder.decode([YabaiSpace].self, from: Fixture.spaces.data())

        #expect(spaces.map(\.index) == Array(1...10))
        #expect(spaces.allSatisfy { $0.display == 1 })

        let visible = spaces.filter(\.isVisible)
        #expect(visible.count == 1)
        #expect(visible.first?.index == 5)
        #expect(visible.first?.hasFocus == true)
        #expect(visible.first?.type == "stack")
        #expect(visible.first?.uuid == "A8D82844-8F16-4F32-9F4D-AC61DF657C2C")

        let spaceTwo = try #require(spaces.first { $0.index == 2 })
        #expect(spaceTwo.type == "bsp")
        #expect(!spaceTwo.hasFocus)
        #expect(!spaceTwo.isVisible)

        #expect(spaces.filter { $0.type == "float" }.map(\.index) == [3, 6])
    }

    @Test("displays decode")
    func displays() throws {
        let displays = try decoder.decode([YabaiDisplay].self, from: Fixture.displays.data())
        let display = try #require(displays.first)

        #expect(display.index == 1)
        #expect(display.uuid == "37D8832A-2D66-02CA-B9F7-8F30A301B230")
        #expect(display.frame == YabaiFrame(x: 0, y: 0, w: 1800, h: 1169))
    }

    @Test("models round-trip through Codable with the kebab-case keys intact")
    func roundTrip() throws {
        let windows = try decoder.decode([YabaiWindow].self, from: Fixture.windowsAll.data())
        let encoded = try JSONEncoder().encode(windows)
        let object = try #require(
            try JSONSerialization.jsonObject(with: encoded) as? [[String: Any]]
        )

        #expect(object.first?["stack-index"] != nil)
        #expect(object.first?["has-focus"] != nil)
        #expect(object.first?["root-window"] != nil)
        #expect(try decoder.decode([YabaiWindow].self, from: encoded) == windows)
    }
}
