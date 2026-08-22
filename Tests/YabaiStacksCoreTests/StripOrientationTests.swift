import Foundation
import Testing
@testable import YabaiStacksCore

@Suite("Vertical strip orientation")
struct StripOrientationTests {
    private let stackFrame = Rect(x: 10, y: 50, width: 1780, height: 1079)
    private let displayFrame = Rect(x: 0, y: 0, width: 1800, height: 1169)

    private func configuration(
        orientation: StripOrientation = .vertical,
        position: StripPosition = .left,
        iconSize: Double = 20,
        iconSpacing: Double = 4,
        padding: Double = 5
    ) -> Configuration {
        Configuration(
            iconSize: iconSize,
            iconSpacing: iconSpacing,
            padding: padding,
            position: position,
            orientation: orientation,
            titlebarInset: 0
        )
    }

    private func layout(_ configuration: Configuration, count: Int = 3) throws -> StripLayout {
        try #require(
            StripGeometry.layout(
                stackFrame: stackFrame,
                windowIDs: Array(0..<count),
                displayFrame: displayFrame,
                configuration: configuration
            )
        )
    }

    @Test("vertical swaps which axis counts the icons")
    func sizeIsTransposed() {
        let vertical = configuration()
        let horizontal = configuration(orientation: .horizontal)

        #expect(StripGeometry.size(iconCount: 4, configuration: vertical) == Size(width: 30, height: 102))
        #expect(StripGeometry.size(iconCount: 4, configuration: horizontal) == Size(width: 102, height: 30))
    }

    @Test("the across axis never depends on the icon count")
    func acrossAxisIsConstant() {
        let vertical = configuration()
        for count in 1...12 {
            #expect(StripGeometry.size(iconCount: count, configuration: vertical).width == 30)
        }
    }

    @Test("icons advance down the y axis and share one x")
    func iconsStackDownwards() throws {
        let strip = try layout(configuration(), count: 4)

        #expect(strip.icons.map(\.minY) == [55, 79, 103, 127])
        #expect(strip.icons.allSatisfy { $0.minX == 15 })
        #expect(strip.icons.allSatisfy { $0.width == 20 && $0.height == 20 })
    }

    /// Icons are laid out in yabai's top-left-origin space, so the first member
    /// has the smallest y and must still read as the topmost icon on screen.
    @Test("the first member stays topmost after conversion to AppKit space")
    func firstMemberIsTopmostOnScreen() throws {
        let strip = try layout(configuration(), count: 3)
        let onScreen = strip.converted(toAppKitWithPrimaryDisplayHeight: 1169)
        let ys = onScreen.icons.map(\.minY)

        #expect(ys == ys.sorted(by: >))
        #expect(try #require(ys.first) > #require(ys.last))
    }

    @Test("hit-testing resolves each icon in a vertical strip")
    func hitTestingDownTheStrip() throws {
        let strip = try layout(configuration(), count: 4)

        #expect(strip.windowID(at: Point(x: 20, y: 60)) == 0)
        #expect(strip.windowID(at: Point(x: 20, y: 84)) == 1)
        #expect(strip.windowID(at: Point(x: 20, y: 132)) == 3)
        // The 4pt gap between icons belongs to neither.
        #expect(strip.windowID(at: Point(x: 20, y: 76)) == nil)
        #expect(strip.windowID(at: Point(x: 20, y: 200)) == nil)
    }

    @Test("with zero spacing a shared horizontal boundary belongs to exactly one icon")
    func sharedBoundaryIsUnambiguous() throws {
        let strip = try layout(configuration(iconSpacing: 0), count: 3)
        let boundary = try #require(strip.icons.first).maxY

        #expect(strip.iconIndex(at: Point(x: 20, y: boundary)) == 1)
        #expect(strip.iconIndex(at: Point(x: 20, y: boundary - 0.001)) == 0)
    }

    @Test("a right-anchored vertical strip uses the transposed width")
    func rightAnchorUsesTransposedWidth() throws {
        let strip = try layout(configuration(position: .right), count: 4)

        #expect(strip.side == .right)
        #expect(strip.frame.maxX == stackFrame.maxX)
        #expect(strip.frame.width == 30)
        #expect(strip.frame.height == 102)
    }

    @Test("a tall vertical strip is clamped to the display's bottom edge")
    func verticalOverflowIsClamped() throws {
        let strip = try layout(configuration(), count: 60)

        #expect(strip.frame.height > displayFrame.height)
        #expect(strip.frame.minY == displayFrame.minY)
    }

    @Test("orientation is the only difference between the two layouts")
    func orientationIsTheOnlyDifference() throws {
        let vertical = try layout(configuration(), count: 5)
        let horizontal = try layout(configuration(orientation: .horizontal), count: 5)

        #expect(vertical.windowIDs == horizontal.windowIDs)
        #expect(vertical.side == horizontal.side)
        #expect(vertical.frame.width == horizontal.frame.height)
        #expect(vertical.frame.height == horizontal.frame.width)
    }
}
