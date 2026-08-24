import Testing
@testable import YabaiStacksCore

/// The pure half of `--hide-on-hover` and of the Mission Control hide: where a
/// strip goes when it gets out of the way, and which strips the cursor is over.
/// The AppKit half — the panel, the event monitor, the animation — has no tests
/// by construction (SPEC: the UI target is manual only).
@Suite("Getting out of the way")
struct HoverGateTests {
    private let screen = Rect(x: 0, y: 0, width: 1800, height: 1169)
    private let leftStrip = Rect(x: 100, y: 900, width: 38, height: 130)
    private let rightStrip = Rect(x: 1650, y: 900, width: 38, height: 130)

    /// A second display to the right of the primary, as `NSScreen.screens`
    /// reports one: origins are global, so the neighbour starts at the
    /// primary's width.
    private let secondScreen = Rect(x: 1800, y: 0, width: 1512, height: 982)

    // MARK: - The desktop

    @Test("the desktop is the union of every screen")
    func desktopUnion() {
        #expect(StripGeometry.desktop(of: []) == nil)
        #expect(StripGeometry.desktop(of: [screen]) == screen)
        #expect(StripGeometry.desktop(of: [screen, secondScreen])
            == Rect(x: 0, y: 0, width: 3312, height: 1169))
    }

    @Test("a screen at a negative origin still lands inside the desktop")
    func desktopWithNegativeOrigin() {
        let left = Rect(x: -1512, y: -200, width: 1512, height: 982)
        let desktop = StripGeometry.desktop(of: [screen, left])
        #expect(desktop == Rect(x: -1512, y: -200, width: 3312, height: 1369))
    }

    // MARK: - Parking

    @Test("a strip leaves by the nearer horizontal edge")
    func parkedExitsTheNearerEdge() {
        #expect(StripGeometry.parked(leftStrip, beyond: screen).maxX < screen.minX)
        #expect(StripGeometry.parked(rightStrip, beyond: screen).minX > screen.maxX)
    }

    @Test("a parked strip is entirely off the desktop and keeps its size")
    func parkedIsFullyOffScreen() {
        for strip in [leftStrip, rightStrip, Rect(x: 890, y: 0, width: 38, height: 130)] {
            let parked = StripGeometry.parked(strip, beyond: screen)
            #expect(parked.width == strip.width)
            #expect(parked.height == strip.height)
            #expect(parked.minY == strip.minY, "parking is horizontal only")
            #expect(parked.maxX <= screen.minX || parked.minX >= screen.maxX)
        }
    }

    /// The multi-display failure: measured against its own screen, a strip on
    /// the second display exits by an edge that is interior to the desktop and
    /// lands fully visible on the primary — where Mission Control is drawing
    /// too. Measured against the desktop it clears every screen.
    @Test("a strip on a second display parks off every screen, not just its own")
    func parkedClearsEveryDisplay() {
        let screens = [screen, secondScreen]
        let desktop = StripGeometry.desktop(of: screens)
        let onSecond = Rect(x: 1810, y: 100, width: 38, height: 130)

        let againstOwnScreen = StripGeometry.parked(onSecond, beyond: secondScreen)
        #expect(screens.contains { $0.contains(Point(x: againstOwnScreen.minX, y: againstOwnScreen.minY)) })

        let againstDesktop = StripGeometry.parked(onSecond, beyond: desktop)
        for screen in screens {
            #expect(againstDesktop.maxX <= screen.minX || againstDesktop.minX >= screen.maxX)
        }
    }

    /// A strip centred exactly on the desktop's centre has no nearer edge; left
    /// is the documented tie-break, matching `.auto` placement.
    @Test("a centred strip parks left")
    func centredStripParksLeft() {
        let centred = Rect(x: screen.midX - 19, y: 100, width: 38, height: 130)
        #expect(StripGeometry.parked(centred, beyond: screen).maxX < screen.minX)
    }

    @Test("without a desktop a strip still clears its own width")
    func parkedWithoutAScreen() {
        let parked = StripGeometry.parked(leftStrip, beyond: nil)
        #expect(parked.maxX < leftStrip.minX)
        #expect(parked.width == leftStrip.width)
    }

    /// The refresh path re-derives placement from the render on every yabai
    /// event. Parking is a pure function of the home rect and the desktop, so a
    /// refresh that lands behind a hide recomputes the same parked rect instead
    /// of the home rect — which is what used to bring every strip back on
    /// screen a frame after it hid.
    @Test("parking is deterministic, so a refresh cannot undo a hide")
    func parkingIsDeterministic() {
        let first = StripGeometry.parked(leftStrip, beyond: screen)
        let second = StripGeometry.parked(leftStrip, beyond: screen)
        #expect(first == second)
        #expect(first != leftStrip)
    }

    @Test("the margin carries the strip clear of the edge rather than flush to it")
    func parkingMargin() {
        #expect(StripGeometry.parkingMargin > 0)
        let flush = StripGeometry.parked(leftStrip, beyond: screen, margin: 0)
        #expect(flush.maxX == screen.minX)
        #expect(StripGeometry.parked(leftStrip, beyond: screen).maxX == screen.minX - StripGeometry.parkingMargin)
    }

    // MARK: - Inset

    @Test("a negative inset grows and a positive one shrinks about the centre")
    func insetBothWays() {
        let rect = Rect(x: 10, y: 20, width: 100, height: 60)
        #expect(rect.insetBy(dx: -5, dy: -5) == Rect(x: 5, y: 15, width: 110, height: 70))
        #expect(rect.insetBy(dx: 10, dy: 10) == Rect(x: 20, y: 30, width: 80, height: 40))
        #expect(rect.insetBy(dx: 0, dy: 0) == rect)
    }

    /// Shrinking past half an edge would otherwise flip that edge past the
    /// other and produce a rect that contains points outside the original.
    @Test("an over-shrunk rect collapses instead of inverting")
    func insetCannotInvert() {
        let collapsed = Rect(x: 10, y: 20, width: 100, height: 60).insetBy(dx: 80, dy: 80)
        #expect(collapsed.width == 0)
        #expect(collapsed.height == 0)
        #expect(!collapsed.contains(Point(x: 60, y: 50)))
    }

    // MARK: - Hover gate

    private var homes: [String: Rect] { ["left": leftStrip, "right": rightStrip] }

    @Test("no cursor means nothing to hide from")
    func noCursor() {
        #expect(HoverGate.hidden(cursor: nil, homes: homes, previouslyHidden: []).isEmpty)
        #expect(HoverGate.hidden(cursor: nil, homes: homes, previouslyHidden: ["left"]).isEmpty)
    }

    @Test("no strips means nothing to hover over")
    func noStrips() {
        #expect(HoverGate.hidden(
            cursor: Point(x: 110, y: 950), homes: [String: Rect](), previouslyHidden: []
        ).isEmpty)
    }

    /// Only the strip under the cursor moves. Hiding all of them would make two
    /// unrelated stacks vanish because the cursor grazed a third.
    @Test("only the strip under the cursor hides")
    func onlyTheHoveredStripHides() {
        #expect(HoverGate.hidden(cursor: Point(x: 110, y: 950), homes: homes, previouslyHidden: []) == ["left"])
        #expect(HoverGate.hidden(cursor: Point(x: 1660, y: 950), homes: homes, previouslyHidden: []) == ["right"])
        #expect(HoverGate.hidden(cursor: Point(x: 900, y: 950), homes: homes, previouslyHidden: []).isEmpty)
    }

    /// Overlap is possible — a narrow leaf's strip may be clamped over its
    /// neighbour's (see `StripGeometry.layout`) — and then both are under the
    /// cursor and both move.
    @Test("overlapping strips both hide")
    func overlappingStripsBothHide() {
        let overlapping = ["a": leftStrip, "b": leftStrip.offsetBy(dx: 4, dy: 0)]
        #expect(HoverGate.hidden(
            cursor: Point(x: 120, y: 950), homes: overlapping, previouslyHidden: []
        ) == ["a", "b"])
    }

    /// The flicker this whole design exists to avoid. Once the strip has moved
    /// out of the way the cursor is no longer over the panel, so a test against
    /// where the panel actually is would answer "not hovered" and bring it
    /// straight back, one event later. The gate tests the home rect, which does
    /// not move, so the answer is stable for a stationary cursor.
    @Test("a stationary cursor over a hidden strip keeps it hidden")
    func hiddenStateIsStable() {
        let cursor = Point(x: 110, y: 950)
        var hidden = HoverGate.hidden(cursor: cursor, homes: homes, previouslyHidden: [])
        #expect(hidden == ["left"])
        for _ in 0..<100 {
            hidden = HoverGate.hidden(cursor: cursor, homes: homes, previouslyHidden: hidden)
            #expect(hidden == ["left"])
        }

        // The parked rect is nowhere near the cursor: testing that instead is
        // precisely the mistake, and it would flip the answer every event.
        #expect(!StripGeometry.parked(leftStrip, beyond: screen).contains(cursor))
    }

    @Test("the cursor leaving brings the strip back")
    func cursorLeavingShows() {
        var hidden = HoverGate.hidden(cursor: Point(x: 110, y: 950), homes: homes, previouslyHidden: [])
        #expect(hidden == ["left"])
        hidden = HoverGate.hidden(cursor: Point(x: 600, y: 300), homes: homes, previouslyHidden: hidden)
        #expect(hidden.isEmpty)
    }

    /// Entering is judged on the exact rect and leaving on the grown one, so a
    /// cursor parked on the boundary settles rather than alternating.
    @Test("the exit margin is hysteresis, not a bigger target")
    func exitMarginIsHysteresis() {
        let justOutside = Point(x: leftStrip.maxX, y: 950)
        #expect(HoverGate.hidden(cursor: justOutside, homes: homes, previouslyHidden: []).isEmpty)
        #expect(HoverGate.hidden(cursor: justOutside, homes: homes, previouslyHidden: ["left"]) == ["left"])

        let wellOutside = Point(x: leftStrip.maxX + HoverGate.exitMargin, y: 950)
        #expect(HoverGate.hidden(cursor: wellOutside, homes: homes, previouslyHidden: ["left"]).isEmpty)
        #expect(HoverGate.exitMargin > 0)
    }

    /// The hysteresis is per strip: being inside one must not widen another.
    @Test("hysteresis applies only to the strip that was hidden")
    func hysteresisIsPerStrip() {
        let justOutsideRight = Point(x: rightStrip.maxX, y: 950)
        #expect(HoverGate.hidden(
            cursor: justOutsideRight, homes: homes, previouslyHidden: ["left"]
        ).isEmpty)
        #expect(HoverGate.hidden(
            cursor: justOutsideRight, homes: homes, previouslyHidden: ["right"]
        ) == ["right"])
    }

    /// A strip that has gone away cannot stay in the hidden set, or a later
    /// stack reusing its key would start out invisible.
    @Test("a strip that no longer exists drops out of the hidden set")
    func removedStripsDropOut() {
        let hidden = HoverGate.hidden(
            cursor: Point(x: 110, y: 950),
            homes: ["left": leftStrip],
            previouslyHidden: ["left", "gone"]
        )
        #expect(hidden == ["left"])
    }
}
