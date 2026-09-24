import os
#if canImport(Darwin)
import Darwin
#endif

/// Lock-backed thread-safe wrapper around any `Sendable` value. Pick the backing mechanism via
/// ``ThreadSafeMechanism``; defaults to `.readerWriterLock` (concurrent reads, exclusive writes).
/// `.lock` is the other option — see ``ThreadSafeMechanism`` for the tradeoffs and measured
/// per-mechanism costs.
///
/// Shape-specific subscripts (`ts[i]`, `dict[k]`) are atomic for the *entire* access under every
/// mechanism, including compound forms like `ts[i] += 1` and `dict[k]?.append(x)` — the write lock
/// is held across the whole get-modify-set via a `_modify` accessor, not just a plain `set`.
///
/// Shape-specific members (`append`/`popLast` for collections, `updateValue`/`removeValue` for
/// dictionaries, etc.) are added via constrained extensions in `ThreadSafe+Collection.swift`,
/// `ThreadSafe+Array.swift`, and `ThreadSafe+Dictionary.swift`.
///
/// Also usable as a property wrapper: `wrappedValue` is a plain-value snapshot (read-only — direct
/// assignment isn't atomic across read-modify-write), and `projectedValue` is this instance itself, so
/// `$name` gives `mutate`/shape-specific members/etc.
@propertyWrapper
public final class ThreadSafe<Value: Sendable>: @unchecked Sendable {
    private enum Backing {
        case lock(OSAllocatedUnfairLock<Void>)
        case readerWriterLock(ReaderWriterLock)
    }

    private let backing: Backing
    // State lives directly on the instance now (not boxed inside the lock) so a subscript
    // `_modify` can `yield &storage[index]` directly — `OSAllocatedUnfairLock.withLock`'s
    // closure-based API doesn't support holding the lock across a `yield`. `read`/`write`/
    // `beginModify` guard every access to it.
    var storage: Value

    // Set right after `beginModify()` acquires its lock/rwlock; checked (and
    // cleared) by `endModify()` before releasing it. `write`/`mutate` can never hit this — their
    // closure parameter type is synchronous, so a caller can't `await` inside it — but a
    // subscript's `_modify` `yield` is exposed to arbitrary caller code, including as `inout` to
    // an `async` function. If that function suspends and the task resumes on a different thread,
    // unlocking from a thread other than the one that locked is undefined behavior for both
    // `os_unfair_lock` and `pthread_rwlock` — this traps deterministically instead of risking UB.
    private var modifyOwnerThread: pthread_t?

    public init(wrappedValue: Value, mechanism: ThreadSafeMechanism = .readerWriterLock) {
        storage = wrappedValue
        switch mechanism {
        case .lock:
            backing = .lock(OSAllocatedUnfairLock())
        case .readerWriterLock:
            backing = .readerWriterLock(ReaderWriterLock())
        }
    }

    public convenience init(_ value: Value, mechanism: ThreadSafeMechanism = .readerWriterLock) {
        self.init(wrappedValue: value, mechanism: mechanism)
    }

    // `.lock` deliberately skips `ReentrancyTracker` entirely: `os_unfair_lock` already traps on a
    // same-thread relock (read-in-read, read-in-write, write-in-read, write-in-write,
    // modify-in-modify — every combination, since every access takes the same lock), so tracking
    // would be pure overhead that duplicates what the lock already guarantees. The trade-off is
    // that `.lock` reentry now crashes with the OS's own message ("Trying to recursively lock an
    // os_unfair_lock...") instead of `trapReentrant()`'s message below — still a deterministic
    // process-terminating trap, just not this codebase's wording. `.readerWriterLock` still needs
    // the tracker: `pthread_rwlock` read-in-read succeeds and only deadlocks once a writer queues,
    // so without tracking that case wouldn't trap at all, it would hang.
    func read<T: Sendable>(_ body: @Sendable (Value) throws -> T) rethrows -> T {
        switch backing {
        case .lock(let lock):
            lock.lock()
            defer { lock.unlock() }
            return try body(storage)
        case .readerWriterLock(let rwLock):
            guard ReentrancyTracker.beginAccess(self) else { Self.trapReentrant() }
            defer { ReentrancyTracker.endAccess(self) }
            rwLock.readLock()
            defer { rwLock.unlock() }
            return try body(storage)
        }
    }

    func write<T: Sendable>(_ body: @Sendable (inout Value) throws -> T) rethrows -> T {
        switch backing {
        case .lock(let lock):
            lock.lock()
            defer { lock.unlock() }
            return try body(&storage)
        case .readerWriterLock(let rwLock):
            guard ReentrancyTracker.beginAccess(self) else { Self.trapReentrant() }
            defer { ReentrancyTracker.endAccess(self) }
            rwLock.writeLock()
            defer { rwLock.unlock() }
            return try body(&storage)
        }
    }

    /// Begins a write-exclusive critical section that a subscript `_modify` accessor holds across
    /// its `yield`. `_modify` can't call `write(_:)`: holding a lock across a coroutine suspension
    /// isn't expressible through a closure-based API, so the lock/rwlock has to be entered
    /// and exited as two separate calls instead. Must be paired with `endModify()`.
    func beginModify() {
        switch backing {
        case .lock(let lock):
            lock.lock()
        case .readerWriterLock(let rwLock):
            guard ReentrancyTracker.beginAccess(self) else { Self.trapReentrant() }
            rwLock.writeLock()
        }
        modifyOwnerThread = pthread_self()
    }

    /// Ends the critical section begun by `beginModify()`.
    func endModify() {
        if let owner = modifyOwnerThread, pthread_equal(owner, pthread_self()) == 0 {
            fatalError("""
            ThreadSafe: a subscript's in-place modify (`ts[i] += 1`, `ts[i]?.append(x)`, plain \
            `ts[i] = v`, etc.) was entered on one thread but is finishing on another. This happens \
            if an `await` suspends while the modify is in progress (e.g. `await f(&ts[i])`) and the \
            task resumes on a different thread — unlocking from a different thread than the one \
            that locked is undefined behavior for both `os_unfair_lock` and `pthread_rwlock`, so \
            this traps instead of risking it. Don't `await` while holding a subscript's in-place \
            modify: copy the value out, `await`, then write it back via the subscript or `mutate`.
            """)
        }
        modifyOwnerThread = nil
        switch backing {
        case .lock(let lock):
            lock.unlock()
        case .readerWriterLock(let rwLock):
            rwLock.unlock()
            ReentrancyTracker.endAccess(self)
        }
    }

    /// Only reachable for `.readerWriterLock` — `.lock` never calls `ReentrancyTracker`, so its
    /// reentry crashes natively via `os_unfair_lock` instead (see the comment above `read(_:)`).
    private static func trapReentrant() -> Never {
        fatalError("""
        ThreadSafe: reentrant access from the same thread. A read/write/subscript-modify was \
        called again on an instance already being read/written/modified on this thread — e.g. \
        from inside `mutate`'s closure, a subscript's in-place modify, or another read/write \
        member. This always deadlocks rather than composing; restructure to avoid calling back \
        into the same ThreadSafe instance while already inside one of its accesses.
        """)
    }

    // If `Value` is a reference type, this (and `elements`/`dictionary`/other shape-specific
    // snapshot accessors) return the same instance, not a copy — mutating through it bypasses
    // the lock entirely. Only value-type `Value`s (Array/Dictionary/Set/String/scalars)
    // get real safety from these accessors.
    public var wrappedValue: Value {
        get { read { $0 } }
        @available(*, unavailable, message: "Direct assignment isn't atomic across read-modify-write; use $name's mutate/etc. instead")
        set {}
    }

    public var projectedValue: ThreadSafe<Value> { self }

    /// Runs `body` as a single unit of work under the lock, so compound
    /// operations (check-then-act, multi-step updates) are atomic — not just each individual call.
    ///
    /// Don't call back into this same instance (`mutate`, `read`-backed members like `count`/`elements`,
    /// a subscript, or any other shape member) from within `body` — the lock is already
    /// held, and re-entry traps deterministically under either mechanism instead of hanging:
    /// natively via `os_unfair_lock` for `.lock`, via `ReentrancyTracker` for `.readerWriterLock`.
    public func mutate<T: Sendable>(_ body: @Sendable (inout Value) throws -> T) rethrows -> T {
        try write(body)
    }
}
