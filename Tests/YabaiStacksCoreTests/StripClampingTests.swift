import Foundation
import Testing
@testable import YabaiStacksCore

/// A strip drawn off-display is clickable over territory it does not label, so
/// placement is clamped to the display even though overflowing the stack frame
/// stays legal.
@Suite("Strip clamping to display bounds")
struct StripClampingTests {
    private let display = Rect(x: 0, y: 0, width: 1800, height: 1169)

    private func configuration(position: StripPosition, iconSize: Double = 18) -> Configuration {
        Configuration(iconSize: iconSize, iconSpacing: 4, padding: 5, position: position, orientation: .horizontal, titlebarInset: 0)
    }

    private func layout(
        position: StripPosition,
        stackFrame: Rect,
        count: Int,
        displayFrame: Rect? = nil
    ) throws -> StripLayout {
        try #require(
            StripGeometry.layout(
                stackFrame: stackFrame,
                windowIDs: Array(0..<count),
                displayFrame: displayFrame ?? display,
                configuration: configuration(position: position)
            )
        )
    }

    @Test("a right-anchored strip that would escape past x = 0 is pulled back on-display")
    func rightAnchorNoLongerEscapesLeft() throws {
        let narrow = Rect(x: 100, y: 200, width: 10, height: 400)
        let strip = try layout(position: .right, stackFrame: narrow, count: 20)

        #expect(strip.frame.minX >= display.minX)
        #expect(strip.frame.maxX <= display.maxX)
        #expect(strip.frame.minX == 0)
    }

    @Test("a left-anchored strip that would escape past the right edge is pulled back")
    func leftAnchorNoLongerEscapesRight() throws {
        let narrow = Rect(x: 1700, y: 200, width: 10, height: 400)
        let strip = try layout(position: .left, stackFrame: narrow, count: 20)

        #expect(strip.frame.maxX <= display.maxX)
        #expect(strip.frame.maxX == display.maxX)
    }

    @Test("clamping slides the strip without resizing it")
    func clampingPreservesSize() throws {
        let narrow = Rect(x: 100, y: 200, width: 10, height: 400)
        let unclamped = StripGeometry.size(iconCount: 20, configuration: configuration(position: .right))
        let strip = try layout(position: .right, stackFrame: narrow, count: 20)

        #expect(strip.frame.width == unclamped.width)
        #expect(strip.frame.height == unclamped.height)
        #expect(strip.count == 20)
    }

    @Test("icons follow the clamped frame rather than the anchor it was pulled from")
    func iconsFollowTheClampedFrame() throws {
        let narrow = Rect(x: 100, y: 200, width: 10, height: 400)
        let strip = try layout(position: .right, stackFrame: narrow, count: 20)
        let first = try #require(strip.icons.first)
        let last = try #require(strip.icons.last)

        #expect(first.minX == strip.frame.minX + 5)
        #expect(last.maxX <= strip.frame.maxX)
        #expect(strip.icons.allSatisfy { $0.minY == strip.frame.minY + 5 })
    }

    @Test("a strip already inside the display is left exactly where it was anchored")
    func fittingStripIsUntouched() throws {
        let frame = Rect(x: 10, y: 50, width: 1780, height: 1079)
        let strip = try layout(position: .left, stackFrame: frame, count: 4)

        #expect(strip.frame.minX == 10)
        #expect(strip.frame.minY == 50)
    }

    @Test("vertical overflow is clamped on both edges")
    func verticalClamping() throws {
        let low = Rect(x: 10, y: -300, width: 400, height: 200)
        #expect(try layout(position: .left, stackFrame: low, count: 3).frame.minY == display.minY)

        let high = Rect(x: 10, y: 1160, width: 400, height: 200)
        let strip = try layout(position: .left, stackFrame: high, count: 3)
        #expect(strip.frame.maxY <= display.maxY)
    }

    /// Nothing fits, so the low edge wins: pushing the origin past it instead
    /// would hide the strip's start and invert the two clamps against each other.
    @Test("a strip wider than the display anchors to the low edge and overflows the high one")
    func oversizedStripDegradesToTheLowEdge() throws {
        let frame = Rect(x: 10, y: 50, width: 1780, height: 1079)
        let strip = try layout(position: .right, stackFrame: frame, count: 200)

        #expect(strip.frame.minX == display.minX)
        #expect(strip.frame.maxX > display.maxX)
        #expect(strip.frame.width > display.width)
    }

    @Test("clamping respects a display at a negative origin")
    func negativeOriginDisplay() throws {
        let secondary = Rect(x: -1920, y: -200, width: 1920, height: 1080)
        let narrow = Rect(x: -1900, y: 0, width: 10, height: 400)
        let strip = try layout(position: .right, stackFrame: narrow, count: 20, displayFrame: secondary)

        #expect(strip.frame.minX >= secondary.minX)
        #expect(strip.frame.maxX <= secondary.maxX)
        #expect(strip.frame.minX == -1920)
    }

    @Test("without a display frame the strip is left unclamped")
    func noDisplayFrameMeansNoClamp() throws {
        let narrow = Rect(x: 100, y: 200, width: 10, height: 400)
        let strip = try #require(
            StripGeometry.layout(
                stackFrame: narrow,
                windowIDs: Array(0..<20),
                displayFrame: nil,
                configuration: configuration(position: .right)
            )
        )

        #expect(strip.frame.minX < 0)
    }

    @Test("clamped is idempotent")
    func clampingIsIdempotent() {
        let rect = Rect(x: -500, y: -500, width: 400, height: 40)
        let once = StripGeometry.clamped(rect, to: display)
        let twice = StripGeometry.clamped(once, to: display)

        #expect(once == twice)
    }
}
