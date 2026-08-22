import Foundation
import Testing
@testable import YabaiStacksCore

@Suite("Rect, Point and Size")
struct RectTests {
    private let rect = Rect(x: 10, y: 20, width: 30, height: 40)

    @Test("edges and centres are distinct in each axis")
    func edges() {
        #expect(rect.minX == 10)
        #expect(rect.minY == 20)
        #expect(rect.maxX == 40)
        #expect(rect.maxY == 60)
        #expect(rect.midX == 25)
        #expect(rect.midY == 40)
        #expect(rect.width == 30)
        #expect(rect.height == 40)
    }

    @Test("containment is half-open, so touching rects never share a point")
    func containment() {
        #expect(rect.contains(Point(x: 10, y: 20)))
        #expect(rect.contains(Point(x: 39.999, y: 59.999)))
        #expect(!rect.contains(Point(x: 40, y: 20)))
        #expect(!rect.contains(Point(x: 10, y: 60)))
        #expect(!rect.contains(Point(x: 9.999, y: 20)))
        #expect(!rect.contains(Point(x: 10, y: 19.999)))

        let neighbour = Rect(x: 40, y: 20, width: 30, height: 40)
        #expect(neighbour.contains(Point(x: 40, y: 20)))
        #expect(!(rect.contains(Point(x: 40, y: 20)) && neighbour.contains(Point(x: 40, y: 20))))
    }

    @Test("offsetBy moves each axis independently")
    func offsetting() {
        #expect(rect.offsetBy(dx: 7, dy: -3) == Rect(x: 17, y: 17, width: 30, height: 40))
        #expect(rect.offsetBy(dx: 0, dy: 5) == Rect(x: 10, y: 25, width: 30, height: 40))
        #expect(rect.offsetBy(dx: 5, dy: 0) == Rect(x: 15, y: 20, width: 30, height: 40))
    }

    @Test("YabaiFrame maps onto Rect without transposing anything")
    func yabaiFrameInterop() {
        let frame = YabaiFrame(x: 10, y: 20, w: 30, h: 40)
        #expect(Rect(frame) == rect)
        #expect(rect.yabaiFrame == frame)
        #expect(Rect(frame).width == 30)
        #expect(Rect(frame).height == 40)
    }
}

@Suite("yabai to AppKit coordinate conversion")
struct GeometryTests {
    /// The user's captured display: 1800x1169 logical, single, primary.
    static let capturedHeight: Double = 1169

    @Test("the captured stack frame lands 40pt above the bottom of the display")
    func capturedFrame() throws {
        let displays = try JSONDecoder().decode([YabaiDisplay].self, from: Fixture.displays.data())
        let display = try #require(displays.first)
        #expect(display.frame == YabaiFrame(x: 0, y: 0, w: 1800, h: 1169))

        let converted = Geometry.appKitRect(
            fromYabai: YabaiFrame(x: 10, y: 50, w: 1780, h: 1079),
            primaryDisplayHeight: display.frame.h
        )
        #expect(converted == Rect(x: 10, y: 40, width: 1780, height: 1079))
    }

    @Test("every component is pinned individually")
    func components() {
        let converted = Geometry.appKitRect(
            fromYabai: Rect(x: 100, y: 200, width: 300, height: 400),
            primaryDisplayHeight: Self.capturedHeight
        )
        #expect(converted.x == 100)
        #expect(converted.y == 569)
        #expect(converted.width == 300)
        #expect(converted.height == 400)
    }

    @Test("the height is subtracted, not ignored")
    func heightParticipates() {
        let short = Geometry.appKitRect(fromYabai: Rect(x: 0, y: 0, width: 10, height: 10), primaryDisplayHeight: 100)
        let tall = Geometry.appKitRect(fromYabai: Rect(x: 0, y: 0, width: 10, height: 20), primaryDisplayHeight: 100)
        #expect(short.y == 90)
        #expect(tall.y == 80)
    }

    @Test("the display edges map to the AppKit edges")
    func displayEdges() {
        let height = Self.capturedHeight
        let atTop = Geometry.appKitRect(fromYabai: Rect(x: 0, y: 0, width: 1800, height: 100), primaryDisplayHeight: height)
        #expect(atTop.maxY == height)
        #expect(atTop.y == 1069)

        let atBottom = Geometry.appKitRect(
            fromYabai: Rect(x: 0, y: height - 100, width: 1800, height: 100),
            primaryDisplayHeight: height
        )
        #expect(atBottom.y == 0)
    }

    @Test("a secondary display above the primary converts above the primary")
    func displayAbove() {
        let height = Self.capturedHeight
        // yabai puts a display above the primary at a negative y.
        let converted = Geometry.appKitRect(
            fromYabai: Rect(x: 0, y: -1080, width: 1920, height: 1080),
            primaryDisplayHeight: height
        )
        #expect(converted.y == height)
        #expect(converted.maxY == 2249)
        #expect(converted.x == 0)

        let window = Geometry.appKitRect(
            fromYabai: Rect(x: 40, y: -1000, width: 800, height: 600),
            primaryDisplayHeight: height
        )
        #expect(window == Rect(x: 40, y: 1569, width: 800, height: 600))
    }

    @Test("a secondary display left of the primary keeps its negative x")
    func displayLeft() {
        let converted = Geometry.appKitRect(
            fromYabai: Rect(x: -1920, y: 0, width: 1920, height: 1080),
            primaryDisplayHeight: Self.capturedHeight
        )
        #expect(converted.x == -1920)
        #expect(converted.y == 89)
        #expect(converted.maxX == 0)

        let window = Geometry.appKitRect(
            fromYabai: Rect(x: -1900, y: 30, width: 500, height: 400),
            primaryDisplayHeight: Self.capturedHeight
        )
        #expect(window == Rect(x: -1900, y: 739, width: 500, height: 400))
    }

    @Test("the conversion is its own inverse")
    func involution() {
        let original = Rect(x: -1900, y: 30, width: 500, height: 400)
        let there = Geometry.appKitRect(fromYabai: original, primaryDisplayHeight: Self.capturedHeight)
        #expect(Geometry.yabaiRect(fromAppKit: there, primaryDisplayHeight: Self.capturedHeight) == original)
        #expect(there != original)
    }

    @Test("points convert without a height to subtract")
    func pointConversion() {
        let converted = Geometry.appKitPoint(fromYabai: Point(x: 10, y: 50), primaryDisplayHeight: Self.capturedHeight)
        #expect(converted == Point(x: 10, y: 1119))
        #expect(Geometry.yabaiPoint(fromAppKit: converted, primaryDisplayHeight: Self.capturedHeight)
            == Point(x: 10, y: 50))
    }

    @Test("converting a rect's origin is not the same as converting the rect")
    func pointIsNotRectOrigin() {
        let rect = Rect(x: 10, y: 50, width: 1780, height: 1079)
        let asRect = Geometry.appKitRect(fromYabai: rect, primaryDisplayHeight: Self.capturedHeight)
        let asPoint = Geometry.appKitPoint(fromYabai: rect.origin, primaryDisplayHeight: Self.capturedHeight)

        #expect(asRect.origin.y == 40)
        #expect(asPoint.y == 1119)
        #expect(asRect.origin != asPoint)
        // The rect's converted top edge is where its origin lands as a point.
        #expect(asRect.maxY == asPoint.y)
    }

    @Test("a zero primary height stays total")
    func degenerateHeight() {
        #expect(Geometry.appKitRect(fromYabai: Rect(x: 5, y: 10, width: 20, height: 30), primaryDisplayHeight: 0)
            == Rect(x: 5, y: -40, width: 20, height: 30))
    }
}

@Suite("Device pixels")
struct DevicePixelsTests {
    @Test("point size times scale, rounded")
    func nominal() {
        #expect(Geometry.devicePixels(pointSize: 18, scale: 1) == 18)
        #expect(Geometry.devicePixels(pointSize: 18, scale: 2) == 36)
        #expect(Geometry.devicePixels(pointSize: 18.4, scale: 1) == 18)
        #expect(Geometry.devicePixels(pointSize: 18.5, scale: 1) == 19)
        #expect(Geometry.devicePixels(pointSize: 512, scale: 2) == 1024)
        #expect(Geometry.devicePixels(pointSize: 1.6, scale: 1) == 2)
    }

    @Test("the result is never below one pixel")
    func lowerBound() {
        for pointSize in [0.0, 0.4, 1.0, 1.4, -18.0, -1e300] {
            #expect(Geometry.devicePixels(pointSize: pointSize, scale: 1) == 1, "\(pointSize)")
        }
        #expect(Geometry.devicePixels(pointSize: 18, scale: 0) == 1)
        #expect(Geometry.devicePixels(pointSize: 18, scale: -2) == 1)
    }

    @Test("absurd inputs saturate instead of trapping the Int conversion")
    func upperBound() {
        #expect(Geometry.devicePixels(pointSize: 1e300, scale: 2) == Geometry.maximumDevicePixels)
        #expect(Geometry.devicePixels(pointSize: 18, scale: 1e300) == Geometry.maximumDevicePixels)
        #expect(Geometry.devicePixels(pointSize: .greatestFiniteMagnitude, scale: .greatestFiniteMagnitude)
            == Geometry.maximumDevicePixels)
        #expect(Geometry.devicePixels(pointSize: 9.3e18, scale: 1) == Geometry.maximumDevicePixels)
        #expect(Geometry.devicePixels(pointSize: 4096, scale: 1) == 4096)
        #expect(Geometry.devicePixels(pointSize: 4095.6, scale: 1) == 4096)
        #expect(Geometry.devicePixels(pointSize: 4097, scale: 1) == Geometry.maximumDevicePixels)
    }

    @Test("non-finite inputs are total")
    func nonFinite() {
        #expect(Geometry.devicePixels(pointSize: .nan, scale: 2) == 1)
        #expect(Geometry.devicePixels(pointSize: 18, scale: .nan) == 1)
        #expect(Geometry.devicePixels(pointSize: .infinity, scale: 1) == Geometry.maximumDevicePixels)
        #expect(Geometry.devicePixels(pointSize: -.infinity, scale: 1) == 1)
        #expect(Geometry.devicePixels(pointSize: .infinity, scale: 0) == 1)
    }

    @Test("the validated configuration range always lands in bounds")
    func configurationRange() {
        for pointSize in [Configuration.minimumIconSize, 18, 64, Configuration.maximumLength] {
            for scale in [1.0, 2.0, 3.0] {
                let pixels = Geometry.devicePixels(pointSize: pointSize, scale: scale)
                #expect(pixels >= Geometry.minimumDevicePixels)
                #expect(pixels <= Geometry.maximumDevicePixels)
                #expect(Double(pixels) == (pointSize * scale).rounded())
            }
        }
    }
}
