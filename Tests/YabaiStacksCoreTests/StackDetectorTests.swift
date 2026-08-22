import Foundation
import Testing
@testable import YabaiStacksCore

/// Builders for the cases no captured fixture covers: two stacks in one space,
/// non-contiguous indices, excluded windows.
enum Synthetic {
    static let leftLeaf = YabaiFrame(x: 10, y: 50, w: 885, h: 1079)
    static let rightLeaf = YabaiFrame(x: 905, y: 50, w: 885, h: 1079)
    /// Left of `rightLeaf` but below both, so y-major and x-major orderings of
    /// the three frames disagree.
    static let lowerLeaf = YabaiFrame(x: 10, y: 600, w: 885, h: 500)

    static func window(
        id: Int,
        app: String = "Code",
        space: Int,
        stackIndex: Int,
        frame: YabaiFrame = leftLeaf,
        display: Int = 1,
        hasFocus: Bool = false,
        isVisible: Bool = true,
        isFloating: Bool = false,
        isMinimized: Bool = false,
        isHidden: Bool = false
    ) -> YabaiWindow {
        YabaiWindow(
            id: id,
            pid: 1000 + id,
            app: app,
            title: "\(app) \(id)",
            frame: frame,
            display: display,
            space: space,
            level: 0,
            subrole: "AXStandardWindow",
            stackIndex: stackIndex,
            isRootWindow: true,
            hasFocus: hasFocus,
            isVisible: isVisible,
            isFloating: isFloating,
            isMinimized: isMinimized,
            isHidden: isHidden,
            isSticky: false
        )
    }

    /// `hasFocus` mirrors real yabai output for readability only: the detector
    /// never reads it, because focus is a window property (SPEC 5).
    static func space(_ index: Int, display: Int = 1, isVisible: Bool = true, hasFocus: Bool = false) -> YabaiSpace {
        YabaiSpace(
            uuid: "space-\(index)",
            index: index,
            type: "bsp",
            display: display,
            hasFocus: hasFocus,
            isVisible: isVisible
        )
    }
}

@Suite("Stack detection")
struct StackDetectorTests {
    private let decoder = JSONDecoder()
    private let detector = StackDetector()

    private func windows(_ fixture: Fixture) throws -> [YabaiWindow] {
        try decoder.decode([YabaiWindow].self, from: fixture.data())
    }

    // MARK: - Captured fixtures

    @Test("windows-stack-visible: one stack, ascending members, 783803 active")
    func capturedVisibleStack() throws {
        let stacks = detector.detect(
            windows: try windows(.windowsStackVisible),
            spaces: [Synthetic.space(2, hasFocus: true)]
        )

        #expect(stacks.count == 1)
        let stack = try #require(stacks.first)
        #expect(stack.members.map(\.id) == [732842, 783797, 783800, 783803])
        #expect(stack.members.map(\.stackIndex) == [1, 2, 3, 4])
        #expect(stack.activeWindowID == 783803)
        #expect(stack.activeMember?.stackIndex == 4)
        #expect(stack.count == 4)
        #expect(stack.space == 2)
        #expect(stack.display == 1)
        #expect(stack.frame == YabaiFrame(x: 10, y: 50, w: 1780, h: 1079))
        #expect(stack.key == StackKey(space: 2, frame: FrameKey(stack.frame)))
    }

    @Test("windows-all: the space-2 stack has no active member when focus is elsewhere (SPEC 5)")
    func capturedStackWithoutFocus() throws {
        let all = try windows(.windowsAll)
        // Space 2 visible on this display while the focused window (577003,
        // space 4) lives elsewhere: legitimately zero active members.
        let stacks = detector.detect(
            windows: all,
            spaces: [Synthetic.space(2)]
        )

        #expect(all.filter(\.hasFocus).map(\.id) == [577003])
        #expect(stacks.count == 1)
        let stack = try #require(stacks.first)
        #expect(stack.activeWindowID == nil)
        #expect(stack.activeMember == nil)
        #expect(stack.members.map(\.id) == [732842, 783797, 783800, 783803])
        #expect(stack.members.allSatisfy { !$0.hasFocus })
    }

    @Test("windows-all with the real space list: space 2 is not visible, so nothing is drawn")
    func capturedStackOnHiddenSpace() throws {
        let spaces = try decoder.decode([YabaiSpace].self, from: Fixture.spaces.data())

        #expect(spaces.filter(\.isVisible).map(\.index) == [5])
        #expect(detector.detect(windows: try windows(.windowsAll), spaces: spaces).isEmpty)
    }

    @Test("windows-all: the visible space 5 holds no stacked windows")
    func capturedVisibleSpaceHasNoStack() throws {
        let stacks = detector.detect(
            windows: try windows(.windowsAll),
            spaces: [Synthetic.space(5)]
        )
        #expect(stacks.isEmpty)
    }

    // MARK: - Grouping

    @Test("two bsp leaves in one space are two stacks (SPEC 2)")
    func twoStacksInOneSpace() throws {
        let stacks = detector.detect(
            windows: [
                Synthetic.window(id: 1, space: 2, stackIndex: 2, frame: Synthetic.leftLeaf),
                Synthetic.window(id: 2, space: 2, stackIndex: 1, frame: Synthetic.leftLeaf),
                Synthetic.window(id: 3, app: "Safari", space: 2, stackIndex: 3, frame: Synthetic.rightLeaf),
                Synthetic.window(id: 4, app: "Safari", space: 2, stackIndex: 1, frame: Synthetic.rightLeaf, hasFocus: true),
                Synthetic.window(id: 5, app: "Safari", space: 2, stackIndex: 2, frame: Synthetic.rightLeaf),
            ],
            spaces: [Synthetic.space(2)]
        )

        #expect(stacks.count == 2)
        let left = try #require(stacks.first)
        let right = try #require(stacks.dropFirst().first)
        #expect(left.frame == Synthetic.leftLeaf)
        #expect(left.members.map(\.id) == [2, 1])
        #expect(left.activeWindowID == nil)
        #expect(right.frame == Synthetic.rightLeaf)
        #expect(right.members.map(\.id) == [4, 5, 3])
        #expect(right.activeWindowID == 4)
    }

    @Test("stacks are ordered by display, then space, then frame y, then x")
    func deterministicOrdering() {
        let windows = [
            Synthetic.window(id: 1, space: 4, stackIndex: 1, frame: Synthetic.rightLeaf, display: 2),
            Synthetic.window(id: 2, space: 4, stackIndex: 2, frame: Synthetic.rightLeaf, display: 2),
            Synthetic.window(id: 3, space: 2, stackIndex: 1, frame: Synthetic.rightLeaf),
            Synthetic.window(id: 4, space: 2, stackIndex: 2, frame: Synthetic.rightLeaf),
            Synthetic.window(id: 5, space: 2, stackIndex: 1, frame: Synthetic.leftLeaf),
            Synthetic.window(id: 6, space: 2, stackIndex: 2, frame: Synthetic.leftLeaf),
            Synthetic.window(id: 7, space: 2, stackIndex: 1, frame: Synthetic.lowerLeaf),
            Synthetic.window(id: 8, space: 2, stackIndex: 2, frame: Synthetic.lowerLeaf),
        ]
        let spaces = [Synthetic.space(2, display: 1), Synthetic.space(4, display: 2)]
        // y-major: (10,50) then (905,50) then (10,600). An x-major key would put
        // (10,600) second, so this ordering pins the priority, not just its
        // determinism.
        let expected = [[5, 6], [3, 4], [7, 8], [1, 2]]

        for _ in 0..<50 {
            let stacks = detector.detect(windows: windows.shuffled(), spaces: spaces)
            #expect(stacks.map { $0.members.map(\.id) } == expected)
            #expect(stacks.map(\.frame) == [Synthetic.leftLeaf, Synthetic.rightLeaf, Synthetic.lowerLeaf, Synthetic.rightLeaf])
            #expect(stacks.map(\.display) == [1, 1, 1, 2])
        }
    }

    @Test("ordering survives a non-finite frame coordinate")
    func orderingWithNonFiniteFrames() {
        let broken = YabaiFrame(x: .nan, y: .nan, w: 100, h: 100)
        let windows = [
            Synthetic.window(id: 1, space: 2, stackIndex: 1, frame: broken),
            Synthetic.window(id: 2, space: 2, stackIndex: 2, frame: broken),
            Synthetic.window(id: 3, space: 2, stackIndex: 1, frame: Synthetic.leftLeaf),
            Synthetic.window(id: 4, space: 2, stackIndex: 2, frame: Synthetic.leftLeaf),
            Synthetic.window(id: 5, space: 2, stackIndex: 1, frame: YabaiFrame(x: .infinity, y: 0, w: 1, h: 1)),
            Synthetic.window(id: 6, space: 2, stackIndex: 2, frame: YabaiFrame(x: .infinity, y: 0, w: 1, h: 1)),
        ]
        let spaces = [Synthetic.space(2)]
        let reference = detector.detect(windows: windows, spaces: spaces)

        #expect(reference.count == 3)
        for _ in 0..<100 {
            #expect(detector.detect(windows: windows.shuffled(), spaces: spaces).map { $0.members.map(\.id) }
                == reference.map { $0.members.map(\.id) })
        }
    }

    @Test("non-contiguous stack indices still sort ascending")
    func nonContiguousIndices() {
        let stacks = detector.detect(
            windows: [
                Synthetic.window(id: 1, space: 2, stackIndex: 9),
                Synthetic.window(id: 2, space: 2, stackIndex: 4),
                Synthetic.window(id: 3, space: 2, stackIndex: 17, hasFocus: true),
            ],
            spaces: [Synthetic.space(2)]
        )

        #expect(stacks.count == 1)
        #expect(stacks.first?.members.map(\.id) == [2, 1, 3])
        #expect(stacks.first?.members.map(\.stackIndex) == [4, 9, 17])
        #expect(stacks.first?.activeWindowID == 3)
    }

    @Test("the stack frame is taken from its members")
    func frameComesFromMembers() {
        let stacks = detector.detect(
            windows: [
                Synthetic.window(id: 1, space: 2, stackIndex: 2, frame: Synthetic.rightLeaf),
                Synthetic.window(id: 2, space: 2, stackIndex: 1, frame: Synthetic.rightLeaf),
            ],
            spaces: [Synthetic.space(2)]
        )
        #expect(stacks.first?.frame == Synthetic.rightLeaf)
    }

    @Test("the display comes from the space, not the window")
    func displayComesFromSpace() {
        let stacks = detector.detect(
            windows: [
                Synthetic.window(id: 1, space: 2, stackIndex: 1, display: 1),
                Synthetic.window(id: 2, space: 2, stackIndex: 2, display: 1),
            ],
            spaces: [Synthetic.space(2, display: 3)]
        )
        #expect(stacks.first?.display == 3)
    }

    // MARK: - Exclusions

    @Test("stack-index 0 is not stacked (SPEC 1)")
    func unstackedWindowsAreIgnored() {
        let stacks = detector.detect(
            windows: [
                Synthetic.window(id: 1, space: 2, stackIndex: 0),
                Synthetic.window(id: 2, space: 2, stackIndex: 0),
                Synthetic.window(id: 3, space: 2, stackIndex: 0, hasFocus: true),
            ],
            spaces: [Synthetic.space(2)]
        )
        #expect(stacks.isEmpty)
    }

    @Test("a floating window is never a stack member")
    func floatingIsExcluded() {
        let members = [
            Synthetic.window(id: 1, space: 2, stackIndex: 1),
            Synthetic.window(id: 2, space: 2, stackIndex: 2),
            Synthetic.window(id: 3, app: "VLC", space: 2, stackIndex: 3, isFloating: true, isMinimized: false),
        ]
        let stacks = detector.detect(windows: members, spaces: [Synthetic.space(2)])

        #expect(stacks.count == 1)
        #expect(stacks.first?.members.map(\.id) == [1, 2])
    }

    @Test("minimised and hidden windows are never stack members")
    func minimisedAndHiddenAreExcluded() {
        let stacks = detector.detect(
            windows: [
                Synthetic.window(id: 1, space: 2, stackIndex: 1),
                Synthetic.window(id: 2, space: 2, stackIndex: 2),
                Synthetic.window(id: 3, space: 2, stackIndex: 3, isMinimized: true),
                Synthetic.window(id: 4, space: 2, stackIndex: 4, isHidden: true),
            ],
            spaces: [Synthetic.space(2)]
        )

        #expect(stacks.first?.members.map(\.id) == [1, 2])
    }

    @Test("excluding a window can drop the stack below the minimum")
    func exclusionCanDropTheStack() {
        let stacks = detector.detect(
            windows: [
                Synthetic.window(id: 1, space: 2, stackIndex: 1),
                Synthetic.window(id: 2, space: 2, stackIndex: 2, isFloating: true),
                Synthetic.window(id: 3, space: 2, stackIndex: 3, isMinimized: true),
            ],
            spaces: [Synthetic.space(2)]
        )
        #expect(stacks.isEmpty)
    }

    @Test("a stack on a non-visible space is dropped (SPEC 7)")
    func hiddenSpaceIsDropped() {
        let windows = [
            Synthetic.window(id: 1, space: 2, stackIndex: 1),
            Synthetic.window(id: 2, space: 2, stackIndex: 2, hasFocus: true),
        ]

        #expect(detector.detect(windows: windows, spaces: [Synthetic.space(2, isVisible: false)]).isEmpty)
        #expect(detector.detect(windows: windows, spaces: [Synthetic.space(2, isVisible: true)]).count == 1)
    }

    @Test("a window on a space that was not queried is dropped")
    func unknownSpaceIsDropped() {
        let stacks = detector.detect(
            windows: [
                Synthetic.window(id: 1, space: 2, stackIndex: 1),
                Synthetic.window(id: 2, space: 2, stackIndex: 2),
            ],
            spaces: [Synthetic.space(5)]
        )
        #expect(stacks.isEmpty)
    }

    @Test("window is-visible is not used as a filter (SPEC 4, SPEC 6)")
    func windowVisibilityIsNotAFilter() {
        let stacks = detector.detect(
            windows: [
                Synthetic.window(id: 1, space: 2, stackIndex: 1, isVisible: false),
                Synthetic.window(id: 2, space: 2, stackIndex: 2, isVisible: false),
            ],
            spaces: [Synthetic.space(2)]
        )
        #expect(stacks.first?.members.map(\.id) == [1, 2])
    }

    // MARK: - Minimum size

    @Test("a stack of one is dropped at the default minimum")
    func singletonIsDropped() {
        let windows = [Synthetic.window(id: 1, space: 2, stackIndex: 1)]

        #expect(detector.detect(windows: windows, spaces: [Synthetic.space(2)]).isEmpty)
        #expect(StackDetector(minStackSize: 1).detect(windows: windows, spaces: [Synthetic.space(2)]).count == 1)
    }

    @Test("minStackSize filters at its exact boundary")
    func minimumBoundary() {
        let windows = (1...3).map { Synthetic.window(id: $0, space: 2, stackIndex: $0) }

        #expect(StackDetector(minStackSize: 3).detect(windows: windows, spaces: [Synthetic.space(2)]).count == 1)
        #expect(StackDetector(minStackSize: 4).detect(windows: windows, spaces: [Synthetic.space(2)]).isEmpty)
    }

    @Test("minStackSize is stored verbatim and defaults to 2")
    func minimumIsStoredVerbatim() {
        #expect(StackDetector().minStackSize == StackDetector.defaultMinStackSize)
        #expect(StackDetector().minStackSize == 2)
        #expect(StackDetector(minStackSize: 0).minStackSize == 0)
        #expect(StackDetector(configuration: Configuration(minStackSize: 5)).minStackSize == 5)

        // Nonsensical minima are rejected by Configuration.validate(), not here;
        // a group always holds at least one window, so they behave as 1.
        let windows = [Synthetic.window(id: 1, space: 2, stackIndex: 1)]
        #expect(StackDetector(minStackSize: 0).detect(windows: windows, spaces: [Synthetic.space(2)]).count == 1)
        #expect(StackDetector(minStackSize: -7).detect(windows: windows, spaces: [Synthetic.space(2)]).count == 1)
    }

    // MARK: - Degenerate input

    @Test("empty inputs produce no stacks")
    func emptyInput() {
        #expect(detector.detect(windows: [], spaces: []).isEmpty)
        #expect(detector.detect(windows: [], spaces: [Synthetic.space(2)]).isEmpty)
        #expect(
            detector.detect(
                windows: [Synthetic.window(id: 1, space: 2, stackIndex: 1)],
                spaces: []
            ).isEmpty
        )
    }

    @Test("duplicate space indices do not duplicate stacks")
    func duplicateSpaces() {
        let stacks = detector.detect(
            windows: [
                Synthetic.window(id: 1, space: 2, stackIndex: 1),
                Synthetic.window(id: 2, space: 2, stackIndex: 2),
            ],
            spaces: [Synthetic.space(2), Synthetic.space(2)]
        )
        #expect(stacks.count == 1)
    }

    @Test("at most one member is active even if two claim focus")
    func atMostOneActive() {
        let stacks = detector.detect(
            windows: [
                Synthetic.window(id: 1, space: 2, stackIndex: 1, hasFocus: true),
                Synthetic.window(id: 2, space: 2, stackIndex: 2, hasFocus: true),
            ],
            spaces: [Synthetic.space(2)]
        )
        #expect(stacks.first?.activeWindowID == 1)
    }

    // MARK: - Value semantics

    @Test("identical inputs produce equal stacks, a focus change does not")
    func equatability() {
        let base = [
            Synthetic.window(id: 1, space: 2, stackIndex: 1, hasFocus: true),
            Synthetic.window(id: 2, space: 2, stackIndex: 2),
        ]
        let moved = [
            Synthetic.window(id: 1, space: 2, stackIndex: 1),
            Synthetic.window(id: 2, space: 2, stackIndex: 2, hasFocus: true),
        ]

        #expect(detector.detect(windows: base, spaces: [Synthetic.space(2)])
            == detector.detect(windows: base.reversed(), spaces: [Synthetic.space(2)]))
        #expect(detector.detect(windows: base, spaces: [Synthetic.space(2)])
            != detector.detect(windows: moved, spaces: [Synthetic.space(2)]))
    }
}

@Suite("Frame keys")
struct FrameKeyTests {
    @Test("equal frames share a key, different frames do not")
    func equality() {
        #expect(FrameKey(Synthetic.leftLeaf) == FrameKey(YabaiFrame(x: 10, y: 50, w: 885, h: 1079)))
        #expect(FrameKey(Synthetic.leftLeaf) != FrameKey(Synthetic.rightLeaf))
        #expect(FrameKey(Synthetic.leftLeaf) != FrameKey(YabaiFrame(x: 10, y: 50, w: 885, h: 1080)))
    }

    @Test("signed zero does not split a key")
    func signedZero() {
        #expect(FrameKey(YabaiFrame(x: -0.0, y: 0, w: 10, h: 10)) == FrameKey(YabaiFrame(x: 0, y: -0.0, w: 10, h: 10)))
    }

    @Test("NaN frames group together instead of vanishing")
    func notANumber() {
        let key = FrameKey(YabaiFrame(x: .nan, y: 0, w: 10, h: 10))
        #expect(key == FrameKey(YabaiFrame(x: .nan, y: 0, w: 10, h: 10)))
        #expect(key.x == Int64.min)
    }

    @Test("infinities saturate without trapping")
    func infinities() {
        #expect(FrameKey.quantise(.infinity) == Int64.max)
        #expect(FrameKey.quantise(-.infinity) == Int64.min + 1)
        #expect(FrameKey.quantise(-.infinity) != FrameKey.quantise(.nan))
        #expect(FrameKey.quantise(1.75) == 1750)
        #expect(FrameKey.quantise(-1.75) == -1750)
        #expect(FrameKey.quantise(Double.greatestFiniteMagnitude) == Int64.max)
    }

    @Test("sub-milli-point noise collapses onto one key")
    func quantisation() {
        #expect(FrameKey(YabaiFrame(x: 10, y: 0, w: 1, h: 1)) == FrameKey(YabaiFrame(x: 10.00001, y: 0, w: 1, h: 1)))
        #expect(FrameKey(YabaiFrame(x: 10, y: 0, w: 1, h: 1)) != FrameKey(YabaiFrame(x: 10.01, y: 0, w: 1, h: 1)))
    }
}
