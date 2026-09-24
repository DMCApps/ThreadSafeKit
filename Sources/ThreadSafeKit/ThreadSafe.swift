import Foundation
import os

/// Lock/queue-backed thread-safe wrapper around any `Sendable` value. Pick the backing mechanism via
/// ``ThreadSafeMechanism``; defaults to a concurrent `DispatchQueue` with barrier writes (reads run in
/// parallel, writes are exclusive).
///
/// Shape-specific members (`append`/`push`/`pop` for collections, `getValue`/`setValue` for dictionaries,
/// etc.) are added via constrained extensions in `ThreadSafe+Collection.swift`, `ThreadSafe+Array.swift`,
/// and `ThreadSafe+Dictionary.swift`.
///
/// Also usable as a property wrapper: `wrappedValue` is a plain-value snapshot (read-only — direct
/// assignment isn't atomic across read-modify-write), and `projectedValue` is this instance itself, so
/// `$name` gives `mutate`/shape-specific members/etc.
@propertyWrapper
public final class ThreadSafe<Value: Sendable>: @unchecked Sendable {
    private enum Backing {
        case lock(OSAllocatedUnfairLock<Value>)
        case queue(DispatchQueue)
    }

    // Per-instance (not static/shared — a shared key would false-positive when nesting into a
    // *different* instance's queue) key that lets `write` detect it's running on this instance's
    // own queue already (e.g. called from a closure passed to `read`) and trap instead of
    // deadlocking: a barrier `sync` nested inside a non-barrier `sync` on the same concurrent
    // queue never triggers libdispatch's own "already owned by current thread" abort, because the
    // outer non-barrier `sync` never claims the drain-owner slot the detector keys off of — it
    // just waits forever for the outer call (its own thread) to finish. See `write` below.
    private let reentrancyKey = DispatchSpecificKey<Void>()

    private let backing: Backing
    // Only used by the `.queue` mechanism — nil under `.lock`, since the lock holds the state itself
    // and only ever touches this through `read`/`write`. Keeping it nil (rather than a duplicate copy
    // of `wrappedValue`) avoids retaining a permanent, unreachable second copy for the object's lifetime.
    private var storage: Value?

    public init(wrappedValue: Value, mechanism: ThreadSafeMechanism = .dispatchQueue) {
        switch mechanism {
        case .lock:
            backing = .lock(OSAllocatedUnfairLock(initialState: wrappedValue))
            storage = nil
        case .dispatchQueue:
            let queue = DispatchQueue(label: "com.threadsafekit.\(Value.self)", attributes: .concurrent)
            queue.setSpecific(key: reentrancyKey, value: ())
            backing = .queue(queue)
            storage = wrappedValue
        }
    }

    public convenience init(_ value: Value, mechanism: ThreadSafeMechanism = .dispatchQueue) {
        self.init(wrappedValue: value, mechanism: mechanism)
    }

    // Takes `Value`, not `inout Value`: this runs on the queue path via a plain (non-barrier) `sync`,
    // so concurrent reads can overlap on a concurrent queue. An `inout` parameter there registers
    // overlapping exclusive accesses to `storage` — a real data race the exclusivity checker/TSan both
    // catch. A by-value snapshot keeps concurrent reads to genuinely non-exclusive access.
    func read<T: Sendable>(_ body: @Sendable (Value) throws -> T) rethrows -> T {
        switch backing {
        case .lock(let lock): return try lock.withLock { try body($0) }
        case .queue(let queue): return try queue.sync { try body(storage!) }
        }
    }

    func write<T: Sendable>(_ body: @Sendable (inout Value) throws -> T) rethrows -> T {
        switch backing {
        case .lock(let lock): return try lock.withLock(body)
        case .queue(let queue):
            // A barrier `sync` nested inside this instance's own non-barrier `read` would hang
            // (see `reentrancyKey`'s doc comment) instead of tripping libdispatch's native
            // same-thread-reentrancy abort, so detect and trap it explicitly here.
            if DispatchQueue.getSpecific(key: reentrancyKey) != nil {
                fatalError("ThreadSafe: reentrant write into an instance already being read/written on the same thread")
            }
            return try queue.sync(flags: .barrier) {
                var value = storage!
                // Drop `storage`'s reference before mutating so `value` is uniquely referenced —
                // otherwise every mutation sees a refcount of 2 and CoW forces a full copy of the
                // whole collection on every write. Safe to nil out: the barrier guarantees no
                // concurrent `read` can be mid-execution to observe the gap.
                storage = nil
                defer { storage = value }
                return try body(&value)
            }
        }
    }

    public var wrappedValue: Value {
        get { read { $0 } }
        @available(*, unavailable, message: "Direct assignment isn't atomic across read-modify-write; use $name's mutate/etc. instead")
        set {}
    }

    public var projectedValue: ThreadSafe<Value> { self }

    /// Runs `body` as a single unit of work under the lock/queue, so compound
    /// operations (check-then-act, multi-step updates) are atomic — not just each individual call.
    ///
    /// Don't call back into this same instance (`mutate`, `read`-backed members like `count`/`elements`,
    /// or any other shape member) from within `body` — the lock/queue is already held, and re-entry
    /// aborts under both mechanisms: `OSAllocatedUnfairLock` self-detects same-thread reentrancy and
    /// traps ("Trying to recursively lock an os_unfair_lock"); `.dispatchQueue` traps via libdispatch
    /// ("dispatch_sync called on queue already owned by current thread"). Neither hangs.
    public func mutate<T: Sendable>(_ body: @Sendable (inout Value) throws -> T) rethrows -> T {
        try write(body)
    }
}
