import Foundation
import Testing
@testable import YabaiStacksCore

@Suite("Strip geometry")
struct StripGeometryTests {
    /// Defaults: icon 18, spacing 4, padding 5.
    private let defaults = Configuration()
    private let stackFrame = Rect(x: 10, y: 50, width: 1780, height: 1079)
    private let displayFrame = Rect(x: 0, y: 0, width: 1800, height: 1169)
    private let ids = [732842, 783797, 783800, 783803]

    private func layout(
        _ configuration: Configuration,
        stackFrame: Rect? = nil,
        ids: [Int]? = nil,
        activeWindowID: Int? = nil,
        displayFrame: Rect? = nil
    ) throws -> StripLayout {
        try #require(
            StripGeometry.layout(
                stackFrame: stackFrame ?? self.stackFrame,
                windowIDs: ids ?? self.ids,
                activeWindowID: activeWindowID,
                displayFrame: displayFrame ?? self.displayFrame,
                configuration: configuration
            )
        )
    }

    private func configuration(
        position: StripPosition = .left,
        iconSize: Double = 18,
        iconSpacing: Double = 4,
        padding: Double = 5,
        offsetX: Double = 0,
        offsetY: Double = 0
    ) -> Configuration {
        Configuration(
            iconSize: iconSize,
            iconSpacing: iconSpacing,
            padding: padding,
            position: position,
            offsetX: offsetX,
            offsetY: offsetY
        )
    }

    // MARK: - Size

    @Test("width counts n icons and n-1 gaps; height never depends on n")
    func stripSize() {
        #expect(StripGeometry.size(iconCount: 1, configuration: defaults) == Size(width: 28, height: 28))
        #expect(StripGeometry.size(iconCount: 2, configuration: defaults) == Size(width: 50, height: 28))
        #expect(StripGeometry.size(iconCount: 4, configuration: defaults) == Size(width: 94, height: 28))
        #expect(StripGeometry.size(iconCount: 7, configuration: defaults).height == 28)
        #expect(StripGeometry.size(iconCount: 7, configuration: defaults).width == 10 + 126 + 24)
    }

    @Test("a single icon has no spacing term and zero counts do not go negative")
    func degenerateSizes() {
        #expect(StripGeometry.size(iconCount: 1, configuration: configuration(iconSpacing: 1000))
            == Size(width: 28, height: 28))
        #expect(StripGeometry.size(iconCount: 0, configuration: defaults) == Size(width: 10, height: 28))
    }

    // MARK: - Anchoring

    @Test("left anchors to the stack frame's top-left")
    func leftAnchor() throws {
        let strip = try layout(configuration(position: .left))
        #expect(strip.side == .left)
        #expect(strip.frame == Rect(x: 10, y: 50, width: 94, height: 28))
        #expect(strip.frame.minX == stackFrame.minX)
        #expect(strip.frame.minY == stackFrame.minY)
    }

    @Test("right anchors to the stack frame's top-right")
    func rightAnchor() throws {
        let strip = try layout(configuration(position: .right))
        #expect(strip.side == .right)
        #expect(strip.frame == Rect(x: 1696, y: 50, width: 94, height: 28))
        #expect(strip.frame.maxX == stackFrame.maxX)
        #expect(strip.frame.minY == stackFrame.minY)
    }

    // MARK: - Auto

    @Test("auto compares the stack centre against its own display's centre")
    func autoSides() {
        let auto = configuration(position: .auto)
        let left = Rect(x: 10, y: 50, width: 885, height: 1079)
        let right = Rect(x: 905, y: 50, width: 885, height: 1079)

        #expect(left.midX == 452.5)
        #expect(right.midX == 1347.5)
        #expect(displayFrame.midX == 900)
        #expect(StripGeometry.side(for: left, position: auto.position, displayFrame: displayFrame) == .left)
        #expect(StripGeometry.side(for: right, position: auto.position, displayFrame: displayFrame) == .right)
    }

    @Test("a stack centred exactly on the display centre resolves left")
    func autoTie() {
        #expect(stackFrame.midX == displayFrame.midX)
        #expect(StripGeometry.side(for: stackFrame, position: .auto, displayFrame: displayFrame) == .left)
        #expect(StripGeometry.side(for: Rect(x: 900.001, y: 0, width: 0, height: 0), position: .auto, displayFrame: displayFrame) == .right)
        #expect(StripGeometry.side(for: Rect(x: 899.999, y: 0, width: 0, height: 0), position: .auto, displayFrame: displayFrame) == .left)
    }

    @Test("auto without a display frame falls back to left")
    func autoWithoutDisplay() throws {
        #expect(StripGeometry.side(for: stackFrame, position: .auto, displayFrame: nil) == .left)
        let strip = try #require(StripGeometry.layout(
            stackFrame: stackFrame, windowIDs: ids, displayFrame: nil, configuration: configuration(position: .auto)
        ))
        #expect(strip.side == .left)
    }

    @Test("explicit sides ignore the display entirely")
    func explicitSidesIgnoreDisplay() {
        for frame in [Rect(x: 0, y: 0, width: 10, height: 10), Rect(x: 1790, y: 0, width: 10, height: 10)] {
            #expect(StripGeometry.side(for: frame, position: .left, displayFrame: displayFrame) == .left)
            #expect(StripGeometry.side(for: frame, position: .right, displayFrame: displayFrame) == .right)
            #expect(StripGeometry.side(for: frame, position: .left, displayFrame: nil) == .left)
        }
    }

    @Test("auto on a display at a negative origin compares against that display, not zero")
    func autoOnNegativeOriginDisplay() throws {
        let secondary = Rect(x: -1920, y: 0, width: 1920, height: 1080)
        let leftHalf = Rect(x: -1920, y: 0, width: 960, height: 1080)
        let rightHalf = Rect(x: -960, y: 0, width: 960, height: 1080)

        #expect(secondary.midX == -960)
        #expect(leftHalf.midX == -1440)
        #expect(rightHalf.midX == -480)
        // Both centres are negative: a rule comparing against 0 would get the
        // right-hand stack wrong.
        #expect(StripGeometry.side(for: leftHalf, position: .auto, displayFrame: secondary) == .left)
        #expect(StripGeometry.side(for: rightHalf, position: .auto, displayFrame: secondary) == .right)

        let strip = try layout(
            configuration(position: .auto), stackFrame: rightHalf, displayFrame: secondary
        )
        #expect(strip.side == .right)
        #expect(strip.frame == Rect(x: -94, y: 0, width: 94, height: 28))
    }

    // MARK: - Offsets

    @Test("offsets push the strip away from the corner it is anchored to")
    func offsets() throws {
        let left = try layout(configuration(position: .left, offsetX: 7, offsetY: -3))
        #expect(left.frame == Rect(x: 17, y: 47, width: 94, height: 28))

        let right = try layout(configuration(position: .right, offsetX: 7, offsetY: -3))
        #expect(right.frame == Rect(x: 1689, y: 47, width: 94, height: 28))

        let negatedRight = try layout(configuration(position: .right, offsetX: -7))
        #expect(negatedRight.frame.x == 1703)
    }

    @Test("a positive offset-y always moves down, on both sides")
    func verticalOffsetIsAlwaysDown() throws {
        for position in [StripPosition.left, .right] {
            let strip = try layout(configuration(position: position, offsetY: 12))
            #expect(strip.frame.y == 62)
        }
    }

    @Test("icons move with the strip")
    func offsetsMoveIcons() throws {
        let plain = try layout(configuration(position: .left))
        let shifted = try layout(configuration(position: .left, offsetX: 7, offsetY: -3))
        #expect(shifted.icons == plain.icons.map { $0.offsetBy(dx: 7, dy: -3) })
    }

    // MARK: - Icon rects

    @Test("icons are laid out left to right at one step per index")
    func iconRects() throws {
        let strip = try layout(configuration(position: .left))
        #expect(strip.icons == [
            Rect(x: 15, y: 55, width: 18, height: 18),
            Rect(x: 37, y: 55, width: 18, height: 18),
            Rect(x: 59, y: 55, width: 18, height: 18),
            Rect(x: 81, y: 55, width: 18, height: 18),
        ])
        #expect(strip.icons.last?.maxX == strip.frame.maxX - 5)
        #expect(strip.icons.allSatisfy { $0.maxY == strip.frame.maxY - 5 })
    }

    @Test("zero spacing makes icons touch, zero padding puts them on the edge")
    func zeroSpacingAndPadding() throws {
        let tight = try layout(configuration(position: .left, iconSpacing: 0), ids: [1, 2, 3])
        #expect(tight.frame.width == 64)
        #expect(tight.icons.map(\.minX) == [15, 33, 51])
        #expect(tight.icons[0].maxX == tight.icons[1].minX)

        let unpadded = try layout(configuration(position: .left, padding: 0), ids: [1, 2, 3])
        #expect(unpadded.frame == Rect(x: 10, y: 50, width: 62, height: 18))
        #expect(unpadded.icons.map(\.minX) == [10, 32, 54])
        #expect(unpadded.icons[0].minY == 50)
    }

    @Test("a single icon fills the strip minus its padding")
    func singleIcon() throws {
        let strip = try layout(configuration(position: .left), ids: [42])
        #expect(strip.frame == Rect(x: 10, y: 50, width: 28, height: 28))
        #expect(strip.icons == [Rect(x: 15, y: 55, width: 18, height: 18)])
        #expect(strip.count == 1)
    }

    @Test("many icons keep a constant step and a constant height")
    func manyIcons() throws {
        let strip = try layout(configuration(position: .left), ids: Array(1...12))
        #expect(strip.icons.count == 12)
        #expect(strip.frame.height == 28)
        for index in 1..<strip.icons.count {
            #expect(strip.icons[index].minX - strip.icons[index - 1].minX == 22)
            #expect(strip.icons[index].minY == strip.icons[0].minY)
        }
    }

    @Test("a strip wider than its stack frame overflows rather than being clamped")
    func overflow() throws {
        let narrow = Rect(x: 100, y: 50, width: 40, height: 40)

        let left = try layout(configuration(position: .left), stackFrame: narrow)
        #expect(left.frame == Rect(x: 100, y: 50, width: 94, height: 28))
        #expect(left.frame.maxX > narrow.maxX)

        let right = try layout(configuration(position: .right), stackFrame: narrow)
        #expect(right.frame == Rect(x: 46, y: 50, width: 94, height: 28))
        #expect(right.frame.minX < narrow.minX)
        #expect(right.frame.maxX == narrow.maxX)
    }

    @Test("an empty stack has no strip")
    func emptyStack() {
        #expect(StripGeometry.layout(
            stackFrame: stackFrame, windowIDs: [], displayFrame: displayFrame, configuration: defaults
        ) == nil)
    }

    // MARK: - Hit-testing

    @Test("points inside an icon resolve to that icon")
    func hitsInsideIcons() throws {
        let strip = try layout(configuration(position: .left))
        #expect(strip.iconIndex(at: Point(x: 15, y: 55)) == 0)
        #expect(strip.iconIndex(at: Point(x: 24, y: 64)) == 0)
        #expect(strip.iconIndex(at: Point(x: 32.999, y: 72.999)) == 0)
        #expect(strip.iconIndex(at: Point(x: 37, y: 55)) == 1)
        #expect(strip.iconIndex(at: Point(x: 59, y: 55)) == 2)
        #expect(strip.iconIndex(at: Point(x: 98.999, y: 55)) == 3)
    }

    @Test("gaps, padding and everything outside resolve to nil")
    func missesResolveToNil() throws {
        let strip = try layout(configuration(position: .left))
        // icon 0 spans x 15..<33, the gap is 33..<37.
        #expect(strip.iconIndex(at: Point(x: 33, y: 55)) == nil)
        #expect(strip.iconIndex(at: Point(x: 36.999, y: 55)) == nil)
        // leading and trailing padding
        #expect(strip.iconIndex(at: Point(x: 14.999, y: 55)) == nil)
        #expect(strip.iconIndex(at: Point(x: 99, y: 55)) == nil)
        // vertical padding, in the strip but above and below the icons
        #expect(strip.iconIndex(at: Point(x: 15, y: 54.999)) == nil)
        #expect(strip.iconIndex(at: Point(x: 15, y: 73)) == nil)
        // outside the strip entirely
        #expect(strip.iconIndex(at: Point(x: 0, y: 0)) == nil)
        #expect(strip.iconIndex(at: Point(x: 104, y: 55)) == nil)
        #expect(strip.iconIndex(at: Point(x: 15, y: 1000)) == nil)
    }

    @Test("no point ever lands in two icons, at any spacing")
    func boundariesAreUnambiguous() throws {
        for spacing in [0.0, 0.5, 4.0] {
            let strip = try layout(configuration(position: .left, iconSpacing: spacing), ids: [1, 2, 3, 4])
            var step = strip.frame.minX - 2
            while step <= strip.frame.maxX + 2 {
                let point = Point(x: step, y: 60)
                let containing = strip.icons.filter { $0.contains(point) }
                #expect(containing.count <= 1, "spacing \(spacing) x \(step) hit \(containing.count) icons")
                #expect(strip.iconIndex(at: point).map { strip.icons[$0] } == containing.first)
                step += 0.25
            }
        }
    }

    @Test("with zero spacing a shared boundary belongs to exactly one icon")
    func touchingBoundary() throws {
        let strip = try layout(configuration(position: .left, iconSpacing: 0), ids: [1, 2, 3])
        #expect(strip.icons[0].maxX == 33)
        #expect(strip.icons[1].minX == 33)
        #expect(strip.iconIndex(at: Point(x: 33, y: 60)) == 1)
        #expect(strip.iconIndex(at: Point(x: 32.999, y: 60)) == 0)
    }

    // MARK: - Window identity

    @Test("icons map back to window ids in member order")
    func windowIdentity() throws {
        let strip = try layout(configuration(position: .left))
        #expect(strip.windowIDs == ids)
        #expect(strip.windowID(forIcon: 0) == 732842)
        #expect(strip.windowID(forIcon: 3) == 783803)
        #expect(strip.windowID(forIcon: 4) == nil)
        #expect(strip.windowID(forIcon: -1) == nil)
        #expect(strip.windowID(at: Point(x: 81, y: 55)) == 783803)
        #expect(strip.windowID(at: Point(x: 33, y: 55)) == nil)
        #expect(strip.iconRect(at: 2) == Rect(x: 59, y: 55, width: 18, height: 18))
        #expect(strip.iconRect(at: 9) == nil)
    }

    @Test("the active member is an index into the strip, and stays optional")
    func activeIndex() throws {
        let focused = try layout(configuration(position: .left), activeWindowID: 783800)
        #expect(focused.activeIndex == 2)
        #expect(focused.activeWindowID == 783800)

        let unfocused = try layout(configuration(position: .left))
        #expect(unfocused.activeIndex == nil)
        #expect(unfocused.activeWindowID == nil)

        let stranger = try layout(configuration(position: .left), activeWindowID: 999)
        #expect(stranger.activeIndex == nil)
    }

    // MARK: - Coordinate space

    @Test("converting flips the whole layout into AppKit space at once")
    func conversion() throws {
        let strip = try layout(configuration(position: .left), activeWindowID: 783803)
        let converted = strip.converted(toAppKitWithPrimaryDisplayHeight: 1169)

        #expect(converted.frame == Rect(x: 10, y: 1091, width: 94, height: 28))
        #expect(converted.icons == [
            Rect(x: 15, y: 1096, width: 18, height: 18),
            Rect(x: 37, y: 1096, width: 18, height: 18),
            Rect(x: 59, y: 1096, width: 18, height: 18),
            Rect(x: 81, y: 1096, width: 18, height: 18),
        ])
        #expect(converted.windowIDs == strip.windowIDs)
        #expect(converted.side == strip.side)
        #expect(converted.activeIndex == 3)
        // The icons stay inside the strip after the flip.
        #expect(converted.icons.allSatisfy { $0.minY >= converted.frame.minY && $0.maxY <= converted.frame.maxY })
    }

    @Test("hit-testing works in the converted space with a converted point")
    func hitTestingAfterConversion() throws {
        let strip = try layout(configuration(position: .left))
        let converted = strip.converted(toAppKitWithPrimaryDisplayHeight: 1169)
        let inIcon2 = Point(x: 60, y: 60)

        #expect(strip.iconIndex(at: inIcon2) == 2)
        #expect(converted.iconIndex(at: Geometry.appKitPoint(fromYabai: inIcon2, primaryDisplayHeight: 1169)) == 2)
        #expect(converted.iconIndex(at: inIcon2) == nil)
    }

    @Test("local icon rects are relative to the strip origin in either space")
    func localIcons() throws {
        let strip = try layout(configuration(position: .left))
        let expected = [
            Rect(x: 5, y: 5, width: 18, height: 18),
            Rect(x: 27, y: 5, width: 18, height: 18),
            Rect(x: 49, y: 5, width: 18, height: 18),
            Rect(x: 71, y: 5, width: 18, height: 18),
        ]

        #expect(strip.localIcons == expected)
        #expect(strip.converted(toAppKitWithPrimaryDisplayHeight: 1169).localIcons == expected)
        #expect(strip.iconIndex(atLocal: Point(x: 5, y: 5)) == 0)
        #expect(strip.iconIndex(atLocal: Point(x: 27, y: 5)) == 1)
        #expect(strip.iconIndex(atLocal: Point(x: 0, y: 0)) == nil)
        #expect(strip.iconIndex(atLocal: Point(x: 23, y: 5)) == nil)
        #expect(strip.windowID(atLocal: Point(x: 71, y: 5)) == 783803)
    }

    // MARK: - Stack and display overloads

    @Test("the Stack overload takes ids and the active member from the stack")
    func stackOverload() throws {
        let members = [
            Synthetic.window(id: 11, space: 2, stackIndex: 1, frame: YabaiFrame(x: 10, y: 50, w: 1780, h: 1079)),
            Synthetic.window(id: 22, space: 2, stackIndex: 2, frame: YabaiFrame(x: 10, y: 50, w: 1780, h: 1079), hasFocus: true),
        ]
        let stack = try #require(StackDetector().detect(windows: members, spaces: [Synthetic.space(2)]).first)
        let strip = try #require(StripGeometry.layout(
            stack: stack, displayFrame: displayFrame, configuration: configuration(position: .left)
        ))

        #expect(strip.windowIDs == [11, 22])
        #expect(strip.activeIndex == 1)
        #expect(strip.frame == Rect(x: 10, y: 50, width: 50, height: 28))
    }

    @Test("the displays overload picks the stack's own display and tolerates a missing one")
    func displaysOverload() throws {
        let members = [
            Synthetic.window(id: 1, space: 4, stackIndex: 1, frame: YabaiFrame(x: -960, y: 0, w: 960, h: 1080), display: 2),
            Synthetic.window(id: 2, space: 4, stackIndex: 2, frame: YabaiFrame(x: -960, y: 0, w: 960, h: 1080), display: 2),
        ]
        let stack = try #require(
            StackDetector().detect(windows: members, spaces: [Synthetic.space(4, display: 2)]).first
        )
        let displays = [
            YabaiDisplay(index: 1, uuid: "primary", frame: YabaiFrame(x: 0, y: 0, w: 1800, h: 1169)),
            YabaiDisplay(index: 2, uuid: "secondary", frame: YabaiFrame(x: -1920, y: 0, w: 1920, h: 1080)),
        ]
        let auto = configuration(position: .auto)

        #expect(try #require(StripGeometry.layout(stack: stack, displays: displays, configuration: auto)).side == .right)
        // Matched against the primary instead, the same stack would go left.
        #expect(try #require(StripGeometry.layout(stack: stack, displays: [displays[0]], configuration: auto)).side == .left)
        #expect(try #require(StripGeometry.layout(stack: stack, displays: [], configuration: auto)).side == .left)
    }

    @Test("captured fixtures: the real 4-window Code stack on the real display")
    func capturedEndToEnd() throws {
        let decoder = JSONDecoder()
        let windows = try decoder.decode([YabaiWindow].self, from: Fixture.windowsStackVisible.data())
        let displays = try decoder.decode([YabaiDisplay].self, from: Fixture.displays.data())
        let stack = try #require(
            StackDetector().detect(windows: windows, spaces: [Synthetic.space(2, hasFocus: true)]).first
        )
        let strip = try #require(StripGeometry.layout(stack: stack, displays: displays, configuration: Configuration()))

        // The stack spans the display, so its centre ties and auto goes left.
        #expect(strip.side == .left)
        #expect(strip.frame == Rect(x: 10, y: 50, width: 94, height: 28))
        #expect(strip.windowIDs == [732842, 783797, 783800, 783803])
        #expect(strip.activeIndex == 3)
        #expect(strip.windowID(at: Point(x: 81, y: 55)) == 783803)

        let onScreen = strip.converted(toAppKitWithPrimaryDisplayHeight: 1169)
        #expect(onScreen.frame == Rect(x: 10, y: 1091, width: 94, height: 28))
        #expect(onScreen.frame.maxY == 1119)
    }
}
