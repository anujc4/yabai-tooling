/// Everything one overlay needs: where it goes, which windows it labels, and
/// the pids its icons are drawn from. `pids` is parallel to `layout.windowIDs`.
///
/// `Hashable` is the whole point — two refreshes that produce an equal render
/// need no work at all, and `StripLayout` and `Stack` are already value types
/// all the way down, so the comparison is exact rather than heuristic.
public struct StripRender: Hashable, Sendable {
    public let key: StackKey
    public let layout: StripLayout
    public let pids: [Int]

    // Internal so `pids` can never be handed in out of step with the layout.
    init(key: StackKey, layout: StripLayout, pids: [Int]) {
        self.key = key
        self.layout = layout
        self.pids = pids
    }

    public var count: Int { layout.count }
    public var windowIDs: [Int] { layout.windowIDs }

    public func pid(forIcon index: Int) -> Int? {
        pids.indices.contains(index) ? pids[index] : nil
    }
}

/// A strip whose panel already exists. `previousKey` is the key that panel is
/// filed under and differs from `render.key` exactly when the stack's frame
/// moved: the frame is part of the identity (SPEC 2), so a resized stack is a
/// new key over the same windows, and the caller re-files the panel rather than
/// destroying it.
public struct StripUpdate: Hashable, Sendable {
    public let previousKey: StackKey
    public let render: StripRender

    init(previousKey: StackKey, render: StripRender) {
        self.previousKey = previousKey
        self.render = render
    }

    public var key: StackKey { render.key }
    public var isRekeyed: Bool { previousKey != render.key }
}

/// Every output list is ordered by the incoming stack order, which
/// `StackDetector` already sorts deterministically; `removed` is sorted by key
/// because a dictionary has no order to inherit.
public struct StripDiff: Hashable, Sendable {
    public let created: [StripRender]
    public let updated: [StripUpdate]
    public let unchanged: [StripRender]
    public let removed: [StackKey]

    init(created: [StripRender], updated: [StripUpdate], unchanged: [StripRender], removed: [StackKey]) {
        self.created = created
        self.updated = updated
        self.unchanged = unchanged
        self.removed = removed
    }

    /// No panel needs creating, moving or destroying. `unchanged` is not work,
    /// so it does not count against emptiness.
    public var isEmpty: Bool { created.isEmpty && updated.isEmpty && removed.isEmpty }

    /// Everything that should be on screen once the diff has been applied.
    public var live: [StripRender] { created + updated.map(\.render) + unchanged }

    /// The state to carry into the next reconciliation.
    public var rendered: [StackKey: StripRender] {
        Dictionary(live.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }
}

/// Diffs one refresh against the last. Refreshes run on every yabai event, so
/// the caller must reuse panels instead of rebuilding them; this decides which
/// is which, and holds no state of its own.
public enum StripReconciler {
    public static func render(
        stack: Stack,
        displays: [YabaiDisplay],
        configuration: Configuration
    ) -> StripRender? {
        guard let layout = StripGeometry.layout(stack: stack, displays: displays, configuration: configuration)
        else { return nil }
        return StripRender(key: stack.key, layout: layout, pids: stack.members.map(\.pid))
    }

    public static func renders(
        for stacks: [Stack],
        displays: [YabaiDisplay],
        configuration: Configuration
    ) -> [StripRender] {
        stacks.compactMap { render(stack: $0, displays: displays, configuration: configuration) }
    }

    public static func reconcile(
        previous: [StackKey: StripRender],
        stacks: [Stack],
        displays: [YabaiDisplay],
        configuration: Configuration
    ) -> StripDiff {
        reconcile(
            previous: previous,
            next: renders(for: stacks, displays: displays, configuration: configuration)
        )
    }

    /// Matching runs in two passes. The first is by key, which is the common
    /// case and must win outright: a different stack that has moved into a key
    /// must not steal the panel already sitting there. Only the leftovers are
    /// then matched by member list, which is what reunites a panel with its
    /// stack after a resize changed the key.
    public static func reconcile(previous: [StackKey: StripRender], next: [StripRender]) -> StripDiff {
        var created: [StripRender] = []
        var unchanged: [StripRender] = []
        var updates: [(index: Int, update: StripUpdate)] = []
        var pending: [(index: Int, render: StripRender)] = []
        var claimed: Set<StackKey> = []
        var seen: Set<StackKey> = []

        for (index, render) in next.enumerated() {
            // Two stacks cannot share a key, but this is a pure function over
            // whatever it is handed; a duplicate would otherwise claim a second
            // panel that nothing would ever remove.
            guard seen.insert(render.key).inserted else { continue }

            guard let existing = previous[render.key] else {
                pending.append((index, render))
                continue
            }
            claimed.insert(render.key)
            if existing == render {
                unchanged.append(render)
            } else {
                updates.append((index, StripUpdate(previousKey: render.key, render: render)))
            }
        }

        var byMembers: [[Int]: StackKey] = [:]
        for (key, render) in previous where !claimed.contains(key) {
            // A window belongs to one stack, so two unclaimed entries cannot
            // share a member list; the tie-break only keeps this deterministic.
            if let existing = byMembers[render.windowIDs], existing < key { continue }
            byMembers[render.windowIDs] = key
        }

        for (index, render) in pending {
            guard let previousKey = byMembers[render.windowIDs], !claimed.contains(previousKey) else {
                created.append(render)
                continue
            }
            claimed.insert(previousKey)
            updates.append((index, StripUpdate(previousKey: previousKey, render: render)))
        }

        return StripDiff(
            created: created,
            updated: updates.sorted { $0.index < $1.index }.map(\.update),
            unchanged: unchanged,
            removed: previous.keys.filter { !claimed.contains($0) }.sorted()
        )
    }
}
