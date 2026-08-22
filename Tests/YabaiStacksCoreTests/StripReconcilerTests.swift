import Foundation
import Testing
@testable import YabaiStacksCore

@Suite("Strip reconciliation")
struct StripReconcilerTests {
    private let displays = [YabaiDisplay(index: 1, uuid: "D1", frame: YabaiFrame(x: 0, y: 0, w: 1800, h: 1169))]
    private let configuration = Configuration(titlebarInset: 0)

    private func stack(
        space: Int = 2,
        frame: YabaiFrame = Synthetic.leftLeaf,
        ids: [Int],
        activeWindowID: Int? = nil
    ) -> Stack {
        let members = ids.enumerated().map { index, id in
            Synthetic.window(id: id, space: space, stackIndex: index + 1, frame: frame)
        }
        return Stack(space: space, display: 1, frame: frame, members: members, activeWindowID: activeWindowID)
    }

    private func renders(_ stacks: [Stack]) -> [StripRender] {
        StripReconciler.renders(for: stacks, displays: displays, configuration: configuration)
    }

    private func reconcile(_ previous: [StripRender], _ stacks: [Stack]) -> StripDiff {
        StripReconciler.reconcile(
            previous: Dictionary(previous.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first }),
            stacks: stacks,
            displays: displays,
            configuration: configuration
        )
    }

    @Test("an empty previous state creates every strip")
    func emptyToPopulated() {
        let stacks = [stack(ids: [1, 2]), stack(space: 3, frame: Synthetic.rightLeaf, ids: [3, 4])]
        let diff = reconcile([], stacks)

        #expect(diff.created.count == 2)
        #expect(diff.updated.isEmpty)
        #expect(diff.unchanged.isEmpty)
        #expect(diff.removed.isEmpty)
        #expect(!diff.isEmpty)
        #expect(diff.created.map(\.windowIDs) == [[1, 2], [3, 4]])
    }

    @Test("an empty refresh removes every strip")
    func populatedToEmpty() throws {
        let previous = renders([stack(ids: [1, 2])])
        let diff = reconcile(previous, [])

        #expect(diff.created.isEmpty)
        #expect(diff.updated.isEmpty)
        #expect(diff.unchanged.isEmpty)
        #expect(diff.removed == [try #require(previous.first).key])
        #expect(diff.live.isEmpty)
    }

    @Test("an identical refresh is entirely unchanged and needs no work")
    func identicalRefreshIsNoWork() {
        let stacks = [stack(ids: [1, 2]), stack(space: 3, frame: Synthetic.rightLeaf, ids: [3, 4])]
        let diff = reconcile(renders(stacks), stacks)

        #expect(diff.isEmpty)
        #expect(diff.unchanged.count == 2)
        #expect(diff.created.isEmpty)
        #expect(diff.updated.isEmpty)
        #expect(diff.removed.isEmpty)
    }

    @Test("a changed active member updates in place without re-creating the panel")
    func activeMemberChangeIsAnUpdate() throws {
        let previous = renders([stack(ids: [1, 2], activeWindowID: 1)])
        let diff = reconcile(previous, [stack(ids: [1, 2], activeWindowID: 2)])

        #expect(diff.created.isEmpty)
        #expect(diff.removed.isEmpty)
        let update = try #require(diff.updated.first)
        #expect(!update.isRekeyed)
        #expect(update.render.layout.activeIndex == 1)
    }

    @Test("gaining a member updates the existing panel rather than replacing it")
    func memberAddedIsAnUpdate() throws {
        let diff = reconcile(renders([stack(ids: [1, 2])]), [stack(ids: [1, 2, 3])])

        #expect(diff.created.isEmpty)
        #expect(diff.removed.isEmpty)
        let update = try #require(diff.updated.first)
        #expect(update.render.count == 3)
        #expect(update.render.pids == [1001, 1002, 1003])
    }

    /// The frame is part of a stack's identity, so a resize changes the key.
    /// The panel must follow its windows instead of being destroyed and rebuilt.
    @Test("a resized stack re-files the same panel under a new key")
    func resizeRekeysRatherThanRecreates() throws {
        let previous = renders([stack(ids: [1, 2])])
        let moved = stack(frame: YabaiFrame(x: 10, y: 50, w: 600, h: 1079), ids: [1, 2])
        let diff = reconcile(previous, [moved])

        #expect(diff.created.isEmpty)
        #expect(diff.removed.isEmpty)
        let update = try #require(diff.updated.first)
        let previousKey = try #require(previous.first).key
        #expect(update.isRekeyed)
        #expect(update.previousKey == previousKey)
        #expect(update.key == moved.key)
    }

    /// A different stack arriving at a key must not inherit the panel already
    /// filed there, or one stack's icons would briefly label another's windows.
    @Test("a key match wins outright over a member match")
    func keyMatchBeatsMemberMatch() throws {
        let occupied = stack(ids: [1, 2])
        let previous = renders([occupied, stack(space: 3, frame: Synthetic.rightLeaf, ids: [7, 8])])
        let diff = reconcile(previous, [stack(ids: [9, 9_1]), stack(space: 3, frame: Synthetic.rightLeaf, ids: [7, 8])])

        let update = try #require(diff.updated.first { $0.key == occupied.key })
        #expect(!update.isRekeyed)
        #expect(update.render.windowIDs == [9, 9_1])
    }

    @Test("a stack that disappears is removed while its neighbour survives")
    func removalLeavesNeighbourAlone() throws {
        let kept = stack(ids: [1, 2])
        let dropped = stack(space: 3, frame: Synthetic.rightLeaf, ids: [3, 4])
        let diff = reconcile(renders([kept, dropped]), [kept])

        #expect(diff.removed == [dropped.key])
        #expect(diff.unchanged.map(\.key) == [kept.key])
        #expect(diff.live.count == 1)
    }

    @Test("output order follows the incoming stack order and removals are sorted")
    func deterministicOrdering() {
        let stacks = (0..<6).map {
            stack(space: $0 + 1, frame: YabaiFrame(x: 10, y: Double($0) * 100, w: 400, h: 90), ids: [$0 * 10, $0 * 10 + 1])
        }
        let previous = renders(stacks)

        for _ in 0..<50 {
            let diff = StripReconciler.reconcile(
                previous: Dictionary(previous.shuffled().map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first }),
                stacks: [],
                displays: displays,
                configuration: configuration
            )
            #expect(diff.removed == diff.removed.sorted())
            #expect(diff.removed.count == 6)
        }

        let created = reconcile([], stacks).created
        #expect(created.map(\.key) == stacks.map(\.key))
    }

    @Test("rendered state round-trips into the next reconciliation")
    func renderedStateCarriesForward() {
        let stacks = [stack(ids: [1, 2])]
        let first = reconcile([], stacks)
        let second = StripReconciler.reconcile(
            previous: first.rendered,
            stacks: stacks,
            displays: displays,
            configuration: configuration
        )

        #expect(second.isEmpty)
        #expect(second.unchanged.count == 1)
    }

    @Test("pids stay parallel to the window ids they are drawn for")
    func pidsAreParallelToWindowIDs() throws {
        let render = try #require(renders([stack(ids: [5, 6, 7])]).first)

        #expect(render.windowIDs == [5, 6, 7])
        #expect(render.pids == [1005, 1006, 1007])
        #expect(render.pid(forIcon: 1) == 1006)
        #expect(render.pid(forIcon: 3) == nil)
        #expect(render.pid(forIcon: -1) == nil)
    }

    @Test("a duplicate key claims only one panel")
    func duplicateKeyIsIgnored() {
        let repeated = stack(ids: [1, 2])
        let diff = reconcile([], [repeated, repeated])

        #expect(diff.created.count == 1)
        #expect(diff.rendered.count == 1)
    }
}
