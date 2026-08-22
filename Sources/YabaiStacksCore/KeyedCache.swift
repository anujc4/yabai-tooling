import Foundation

/// A least-recently-used cache holding the whole keying and eviction policy, so
/// the icon cache's behaviour is testable without AppKit. The icon adapter in
/// the UI target supplies the loader and nothing else.
///
/// Deliberately not `Sendable`: the loader is an ordinary closure, so a
/// conformance would launder whatever non-Sendable state it captures. The one
/// consumer holds a cache privately on the main actor.
public final class KeyedCache<Key: Hashable, Value> {
    public typealias Loader = (Key) -> Value?

    public let capacity: Int

    private let lock = NSLock()
    private let load: Loader

    /// A failed load is cached as `.some(nil)` so one refresh cannot hammer a
    /// key that cannot be resolved. It is not cached across refreshes: `retain`
    /// drops misses, because an app queried mid-launch has no icon yet and must
    /// get one on the next event rather than staying blank while it is visible.
    private var entries: [Key: Value?] = [:]
    private var recency: [Key] = []

    /// The loader runs while the lock is held: that is what makes "at most one
    /// load per key" true, and it means the loader must not re-enter the cache.
    public init(capacity: Int, load: @escaping Loader) {
        self.capacity = max(1, capacity)
        self.load = load
    }

    public func value(for key: Key) -> Value? {
        assertNotReentrant()
        lock.lock()
        defer { lock.unlock() }

        if let cached = entries[key] {
            touch(key)
            return cached
        }

        markLoading(true)
        let loaded = load(key)
        markLoading(false)

        entries[key] = .some(loaded)
        recency.append(key)
        evictIfNeeded()
        return loaded
    }

    public func contains(_ key: Key) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return entries[key] != nil
    }

    /// Drops every key outside `keys`, which is how a refresh forgets apps that
    /// are no longer on screen, and drops cached misses among the survivors so
    /// the next refresh retries them.
    public func retain(_ keys: some Sequence<Key>) {
        let kept = Set(keys)
        lock.lock()
        defer { lock.unlock() }
        entries = entries.filter { kept.contains($0.key) && $0.value != nil }
        recency.removeAll { entries[$0] == nil }
    }

    public func invalidate(_ key: Key) {
        lock.lock()
        defer { lock.unlock() }
        entries.removeValue(forKey: key)
        recency.removeAll { $0 == key }
    }

    public func invalidateAll() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
        recency.removeAll()
    }

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }

    /// Least recently used first.
    public var cachedKeys: [Key] {
        lock.lock()
        defer { lock.unlock() }
        return recency
    }

    private func touch(_ key: Key) {
        guard let index = recency.firstIndex(of: key) else { return }
        recency.remove(at: index)
        recency.append(key)
    }

    private func evictIfNeeded() {
        while recency.count > capacity, let oldest = recency.first {
            recency.removeFirst()
            entries.removeValue(forKey: oldest)
        }
    }

    // A re-entrant loader deadlocks on the non-recursive lock, which surfaces as
    // a frozen process rather than a stack trace. The thread is recorded, not a
    // flag: a second thread waiting on the lock is legitimate, the same thread
    // arriving twice is not. Debug-only, so release builds pay nothing.
    #if DEBUG
    private let reentrancyLock = NSLock()
    private var loadingThread: Thread?
    #endif

    private func assertNotReentrant() {
        #if DEBUG
        reentrancyLock.lock()
        let reentrant = loadingThread === Thread.current
        reentrancyLock.unlock()
        assert(!reentrant, "KeyedCache loader must not call back into the same cache")
        #endif
    }

    private func markLoading(_ loading: Bool) {
        #if DEBUG
        reentrancyLock.lock()
        loadingThread = loading ? Thread.current : nil
        reentrancyLock.unlock()
        #endif
    }
}
