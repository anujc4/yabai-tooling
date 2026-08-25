/// Which strips the cursor is over: judged against each strip's home rect, never
/// its live frame: a parked strip is never under the cursor.
public enum HoverGate {
    /// Entering is judged on the exact home rect and leaving on it grown by this much,
    /// so a cursor on the boundary settles.
    public static let exitMargin: Double = 2

    public static func hidden<Key: Hashable>(
        cursor: Point?,
        homes: [Key: Rect],
        previouslyHidden: Set<Key>,
        margin: Double = exitMargin
    ) -> Set<Key> {
        guard let cursor else { return [] }
        return Set(
            homes
                .filter { key, home in
                    let grow = previouslyHidden.contains(key) ? -margin : 0
                    return home.insetBy(dx: grow, dy: grow).contains(cursor)
                }
                .keys
        )
    }
}
