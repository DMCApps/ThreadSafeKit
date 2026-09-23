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
            backing = .queue(DispatchQueue(label: "com.threadsafekit.\(Value.self)", attributes: .concurrent))
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
            return try queue.sync(flags: .barrier) {
                var value = storage!
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
