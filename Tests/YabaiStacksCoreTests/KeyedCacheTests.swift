import Dispatch
import Foundation
import Testing
@testable import YabaiStacksCore

/// Records every load so "at most one load per key" can be asserted directly.
/// Locked independently of the cache so that a cache which lost its own lock
/// fails on duplicate keys rather than on a corrupted array.
private final class LoadRecorder {
    private let lock = NSLock()
    private var recorded: [Int] = []

    var missing: Set<Int> = []

    /// Widens the window in which a second thread can enter an unsynchronised
    /// loader; with the cache's lock in place the count stays exactly one.
    var loadDelay: TimeInterval = 0

    var keys: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    var count: Int { keys.count }

    func load(_ key: Int) -> String? {
        lock.lock()
        recorded.append(key)
        lock.unlock()
        if loadDelay > 0 { Thread.sleep(forTimeInterval: loadDelay) }
        return missing.contains(key) ? nil : "app-\(key)"
    }
}

@Suite("Keyed cache")
struct KeyedCacheTests {
    private func makeCache(
        capacity: Int = 8
    ) -> (KeyedCache<Int, String>, LoadRecorder) {
        let recorder = LoadRecorder()
        return (KeyedCache(capacity: capacity) { recorder.load($0) }, recorder)
    }

    @Test("a miss loads, a hit does not")
    func hitsAndMisses() {
        let (cache, recorder) = makeCache()

        #expect(cache.value(for: 1) == "app-1")
        #expect(recorder.count == 1)
        #expect(cache.value(for: 1) == "app-1")
        #expect(cache.value(for: 1) == "app-1")
        #expect(recorder.count == 1)
        #expect(recorder.keys == [1])
        #expect(cache.count == 1)
    }

    @Test("each key is loaded exactly once, whatever the access order")
    func oneLoadPerKey() {
        let (cache, recorder) = makeCache()

        for key in [1, 2, 1, 3, 2, 1, 3, 3, 2] {
            _ = cache.value(for: key)
        }

        #expect(recorder.keys == [1, 2, 3])
        #expect(cache.count == 3)
    }

    @Test("distinct keys get distinct values")
    func distinctKeys() {
        let (cache, recorder) = makeCache()

        #expect(cache.value(for: 7) == "app-7")
        #expect(cache.value(for: 9) == "app-9")
        #expect(recorder.keys == [7, 9])
    }

    @Test("a refresh retries a key that could not be resolved")
    func missesAreRetriedOnRefresh() {
        let (cache, recorder) = makeCache()
        recorder.missing = [5]
        _ = cache.value(for: 6)

        #expect(cache.value(for: 5) == nil)
        #expect(recorder.keys == [6, 5])

        // An app queried mid-launch has no icon yet; the next refresh must ask
        // again rather than leaving it blank for as long as it is on screen.
        recorder.missing = []
        cache.retain([5, 6])
        #expect(!cache.contains(5))
        #expect(cache.contains(6))
        #expect(cache.value(for: 5) == "app-5")
        #expect(recorder.keys == [6, 5, 5])

        // The resolved value is now sticky across refreshes.
        cache.retain([5, 6])
        #expect(cache.value(for: 5) == "app-5")
        #expect(recorder.keys == [6, 5, 5])
    }

    @Test("retain keeps resolved values and drops only the misses")
    func retainDropsOnlyMisses() {
        let (cache, recorder) = makeCache()
        recorder.missing = [2, 4]
        for key in 1...4 { _ = cache.value(for: key) }

        #expect(cache.count == 4)
        cache.retain([1, 2, 3, 4])
        #expect(cache.count == 2)
        #expect(cache.cachedKeys == [1, 3])
        #expect(recorder.count == 4)
    }

    @Test("a key that cannot be resolved is not retried within one refresh")
    func negativeCaching() {
        let (cache, recorder) = makeCache()
        recorder.missing = [5]

        #expect(cache.value(for: 5) == nil)
        #expect(cache.value(for: 5) == nil)
        #expect(recorder.count == 1)
        #expect(cache.contains(5))
        #expect(cache.count == 1)
    }

    @Test("invalidate forces exactly one reload")
    func invalidation() {
        let (cache, recorder) = makeCache()

        _ = cache.value(for: 1)
        _ = cache.value(for: 2)
        cache.invalidate(1)

        #expect(!cache.contains(1))
        #expect(cache.contains(2))
        #expect(cache.count == 1)
        #expect(cache.value(for: 1) == "app-1")
        #expect(recorder.keys == [1, 2, 1])
        #expect(cache.value(for: 2) == "app-2")
        #expect(recorder.count == 3)
    }

    @Test("invalidating an absent key is a no-op")
    func invalidateAbsent() {
        let (cache, recorder) = makeCache()
        _ = cache.value(for: 1)
        cache.invalidate(99)

        #expect(cache.count == 1)
        #expect(cache.value(for: 1) == "app-1")
        #expect(recorder.count == 1)
    }

    @Test("invalidateAll empties the cache")
    func invalidateEverything() {
        let (cache, recorder) = makeCache()
        _ = cache.value(for: 1)
        _ = cache.value(for: 2)
        cache.invalidateAll()

        #expect(cache.count == 0)
        #expect(cache.cachedKeys.isEmpty)
        #expect(cache.value(for: 1) == "app-1")
        #expect(recorder.count == 3)
    }

    @Test("the least recently used key is evicted at capacity")
    func eviction() {
        let (cache, recorder) = makeCache(capacity: 2)

        _ = cache.value(for: 1)
        _ = cache.value(for: 2)
        _ = cache.value(for: 3)

        #expect(cache.cachedKeys == [2, 3])
        #expect(cache.count == 2)
        #expect(!cache.contains(1))
        #expect(cache.value(for: 1) == "app-1")
        #expect(recorder.keys == [1, 2, 3, 1])
        #expect(cache.cachedKeys == [3, 1])
    }

    @Test("a hit refreshes recency, so the other key is evicted instead")
    func hitsUpdateRecency() {
        let (cache, recorder) = makeCache(capacity: 2)

        _ = cache.value(for: 1)
        _ = cache.value(for: 2)
        #expect(cache.cachedKeys == [1, 2])
        _ = cache.value(for: 1)
        #expect(cache.cachedKeys == [2, 1])
        _ = cache.value(for: 3)

        #expect(cache.cachedKeys == [1, 3])
        #expect(!cache.contains(2))
        #expect(recorder.keys == [1, 2, 3])
    }

    @Test("capacity is honoured exactly, not approximately")
    func capacityBoundary() {
        let (cache, _) = makeCache(capacity: 3)

        for key in 1...3 { _ = cache.value(for: key) }
        #expect(cache.count == 3)
        #expect(cache.cachedKeys == [1, 2, 3])

        _ = cache.value(for: 4)
        #expect(cache.count == 3)
        #expect(cache.cachedKeys == [2, 3, 4])
    }

    @Test("capacity is clamped to at least one entry")
    func capacityClamping() {
        let (cache, _) = makeCache(capacity: 0)
        #expect(cache.capacity == 1)

        _ = cache.value(for: 1)
        _ = cache.value(for: 2)
        #expect(cache.cachedKeys == [2])
        #expect(cache.count == 1)

        let (negative, _) = makeCache(capacity: -5)
        #expect(negative.capacity == 1)
        #expect(KeyedCache<Int, String>(capacity: 64) { _ in nil }.capacity == 64)
    }

    @Test("retain drops every key that is no longer on screen")
    func retaining() {
        let (cache, recorder) = makeCache()
        for key in 1...4 { _ = cache.value(for: key) }

        cache.retain([2, 4, 77])

        #expect(cache.count == 2)
        #expect(cache.cachedKeys == [2, 4])
        #expect(!cache.contains(1))
        #expect(cache.contains(4))
        #expect(cache.value(for: 2) == "app-2")
        #expect(recorder.count == 4)
    }

    @Test("retaining nothing empties the cache")
    func retainNothing() {
        let (cache, _) = makeCache()
        _ = cache.value(for: 1)
        cache.retain([Int]())

        #expect(cache.count == 0)
        #expect(cache.cachedKeys.isEmpty)
    }

    @Test("retain preserves recency order among the survivors")
    func retainKeepsOrder() {
        let (cache, _) = makeCache()
        for key in [1, 2, 3, 4] { _ = cache.value(for: key) }
        _ = cache.value(for: 2)

        #expect(cache.cachedKeys == [1, 3, 4, 2])
        cache.retain([1, 2, 4])
        #expect(cache.cachedKeys == [1, 4, 2])
    }

    @Test("concurrent lookups still load each key exactly once")
    func concurrentLoads() {
        let (cache, recorder) = makeCache(capacity: 64)
        recorder.loadDelay = 0.002

        // KeyedCache does not advertise Sendable — the loader is an ordinary
        // closure — but it is NSLock-guarded, which is what this test exercises.
        let shared = Unsafe(cache)
        DispatchQueue.concurrentPerform(iterations: 400) { iteration in
            _ = shared.value.value(for: iteration % 8)
        }
        recorder.loadDelay = 0

        #expect(recorder.keys.sorted() == Array(0..<8))
        #expect(recorder.count == 8)
        #expect(cache.count == 8)
        #expect(Set(cache.cachedKeys) == Set(0..<8))
        for key in 0..<8 { #expect(cache.value(for: key) == "app-\(key)") }
        #expect(recorder.count == 8)
    }

    @Test("a cached miss still occupies capacity and is evicted like a hit")
    func missesParticipateInEviction() {
        let (cache, recorder) = makeCache(capacity: 2)
        recorder.missing = [1]

        #expect(cache.value(for: 1) == nil)
        _ = cache.value(for: 2)
        _ = cache.value(for: 3)

        #expect(cache.cachedKeys == [2, 3])
        #expect(!cache.contains(1))
        #expect(cache.value(for: 1) == nil)
        #expect(recorder.keys == [1, 2, 3, 1])
    }
}

private struct Unsafe<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
