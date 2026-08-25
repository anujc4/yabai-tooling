import Foundation

/// An LRU cache. Deliberately not `Sendable`: the loader is an ordinary closure,
/// so a conformance would launder whatever non-Sendable state it captures.
public final class KeyedCache<Key: Hashable, Value> {
    public typealias Loader = (Key) -> Value?

    public let capacity: Int

    private let lock = NSLock()
    private let load: Loader

    /// A failed load is cached as `.some(nil)`, so one refresh cannot hammer a key.
    private var entries: [Key: Value?] = [:]
    private var recency: [Key] = []

    /// The loader runs while the lock is held, so it must not re-enter the cache.
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

    /// Drops every key outside `keys`, and cached misses among the survivors, so a
    /// key that could not be resolved is retried on the next refresh.
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

    // A thread rather than a flag: a second thread waiting on the lock is legitimate,
    // the same thread arriving twice is a deadlock.
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
