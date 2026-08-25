/// Everything one overlay needs; `pids` is parallel to `layout.windowIDs`.
/// `Hashable` so two refreshes producing an equal render need no work at all.
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

/// A strip whose panel already exists. `previousKey` differs from `render.key`
/// exactly when the frame moved: the frame is part of the identity (SPEC 2).
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

/// Ordered by the incoming stack order; `removed` is sorted by key.
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

    /// `unchanged` is not work, so it does not count against emptiness.
    public var isEmpty: Bool { created.isEmpty && updated.isEmpty && removed.isEmpty }

    public var live: [StripRender] { created + updated.map(\.render) + unchanged }

    public var rendered: [StackKey: StripRender] {
        Dictionary(live.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }
}

/// Diffs one refresh against the last so panels are reused, not rebuilt. Stateless.
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

    /// Two passes. By key first, which must win outright so a different stack that
    /// moved into a key cannot steal its panel; leftovers then match by member list.
    public static func reconcile(previous: [StackKey: StripRender], next: [StripRender]) -> StripDiff {
        var created: [StripRender] = []
        var unchanged: [StripRender] = []
        var updates: [(index: Int, update: StripUpdate)] = []
        var pending: [(index: Int, render: StripRender)] = []
        var claimed: Set<StackKey> = []
        var seen: Set<StackKey> = []

        for (index, render) in next.enumerated() {
            // Pure function over whatever it is handed: a duplicate key would
            // otherwise claim a second panel that nothing would ever remove.
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
            // Two unclaimed entries cannot really share a member list; the tie-break
            // only keeps this deterministic.
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
