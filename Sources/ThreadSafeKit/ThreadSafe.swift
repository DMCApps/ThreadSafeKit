import os
#if canImport(Darwin)
import Darwin
#endif

/// Lock-backed thread-safe wrapper around any `Sendable` value. Pick the backing mechanism via
/// ``ThreadSafeMechanism``; defaults to `.lock` (every access exclusive). `.readerWriterLock`
/// (concurrent reads, exclusive writes) is faster when many threads read a large collection at
/// once — see ``ThreadSafeMechanism`` for when to pick it and the measured costs.
///
/// Shape-specific subscripts (`ts[i]`, `dict[k]`) are atomic for the *entire* access under every
/// mechanism, including compound forms like `ts[i] += 1` and `dict[k]?.append(x)` — the write lock
/// is held across the whole get-modify-set via a `_modify` accessor, not just a plain `set`.
///
/// Shape-specific members (`append`/`popLast` for collections, `updateValue`/`removeValue` for
/// dictionaries, etc.) are added via constrained extensions in the `ThreadSafe+*.swift` files.
///
/// Also usable as a property wrapper: `wrappedValue` is a plain-value snapshot (read-only — direct
/// assignment isn't atomic across read-modify-write), and `projectedValue` is this instance itself, so
/// `$name` gives `mutate`/shape-specific members/etc.
@propertyWrapper
public final class ThreadSafe<Value: Sendable>: @unchecked Sendable {
    // Every public member (plus `read`/`write`/`beginModify`/`endModify`) is `@inlinable` so a
    // client module can specialize it for its concrete `Value`; unspecialized, each call paid
    // ~40–200ns of generic dispatch on top of the lock (see `ThreadSafeKitBenchmarks`). Everything
    // they touch is `@usableFromInline` for that reason — don't make it `private`, and mark new
    // public members `@inlinable` too.
    //
    // The four actor types (`ThreadSafeArray`, `ThreadSafeDictionary`, `ThreadSafeSet`,
    // `ThreadSafeAtomic`) follow the same rule and are `public final actor`s for the same reason,
    // plus one more that's specific to actors: Swift doesn't treat actors as implicitly `final`, so
    // a call through a captured instance (e.g. inside a `@Sendable` closure passed to a `Task`,
    // which is how the contended benchmarks and most real callers use them) compiles to a vtable
    // call into the unspecialized generic method — `@inlinable` alone can't fix that, since the
    // compiler can't devirtualize and inline a call it can't statically resolve. `final` makes the
    // call resolvable again. See the doc comment at the top of each actor file for the details;
    // don't remove `final` from any of them, and don't make their storage `private` again.
    @usableFromInline
    enum Backing {
        case lock(OSAllocatedUnfairLock<Void>)
        case readerWriterLock(ReaderWriterLock)
    }

    @usableFromInline
    let backing: Backing
    // State lives on the instance (not as `OSAllocatedUnfairLock`'s own state) so a subscript
    // `_modify` can `yield &storage[index]` directly — the lock's state is only reachable inside
    // the closure passed to `withLock`, which can't span a `yield`. `read`/`write`/`beginModify`
    // guard every access to it.
    @usableFromInline
    var storage: Value

    // Set right after `beginModify()` acquires its lock/rwlock; checked (and
    // cleared) by `endModify()` before releasing it. `write`/`mutate` can never hit this — their
    // closure parameter type is synchronous, so a caller can't `await` inside it — but a
    // subscript's `_modify` `yield` is exposed to arbitrary caller code, including as `inout` to
    // an `async` function. If that function suspends and the task resumes on a different thread,
    // unlocking from a thread other than the one that locked is undefined behavior for both
    // `os_unfair_lock` and `pthread_rwlock` — this traps deterministically instead of risking UB.
    // If the task instead resumes on the *same* thread (always true on `@MainActor`, and possible
    // elsewhere), this check can't see it: `pthread_equal` matches, so nothing trips. The write lock
    // just stays held for the whole `await`, blocking every other thread's access to this instance
    // and tripping `ReentrancyTracker`/`os_unfair_lock`'s own reentry trap for any other task that
    // touches this instance from that same thread in the meantime.
    @usableFromInline
    var modifyOwnerThread: pthread_t?

    @inlinable
    public init(wrappedValue: Value, mechanism: ThreadSafeMechanism = .lock) {
        storage = wrappedValue
        switch mechanism {
        case .lock:
            backing = .lock(OSAllocatedUnfairLock())
        case .readerWriterLock:
            backing = .readerWriterLock(ReaderWriterLock())
        }
    }

    @inlinable
    public convenience init(_ value: Value, mechanism: ThreadSafeMechanism = .lock) {
        self.init(wrappedValue: value, mechanism: mechanism)
    }

    // `.lock` deliberately skips `ReentrancyTracker` entirely: `os_unfair_lock` already traps on a
    // same-thread relock (read-in-read, read-in-write, write-in-read, write-in-write,
    // modify-in-modify — every combination, since every access takes the same lock), so tracking
    // would be pure overhead that duplicates what the lock already guarantees. The trade-off is
    // that `.lock` reentry crashes with the OS's own message ("BUG IN CLIENT OF LIBPLATFORM: Trying
    // to recursively lock an os_unfair_lock", in the crash report) instead of `trapReentrant()`'s
    // message below — still a deterministic process-terminating trap, just not this codebase's
    // wording. `.readerWriterLock` needs the tracker: on Darwin, `pthread_rwlock` write-in-read
    // hangs outright, and read-in-read succeeds but deadlocks once a writer queues, so without
    // tracking those cases would hang instead of trapping.
    @inlinable
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

    @inlinable
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
    @inlinable
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
    @inlinable
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
    @usableFromInline
    static func trapReentrant() -> Never {
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
    @inlinable
    public var wrappedValue: Value {
        get { read { $0 } }
        @available(*, unavailable, message: "Direct assignment isn't atomic across read-modify-write; use $name's mutate/etc. instead")
        set {}
    }

    @inlinable
    public var projectedValue: ThreadSafe<Value> { self }

    /// Runs `body` as a single unit of work under the lock, so compound
    /// operations (check-then-act, multi-step updates) are atomic — not just each individual call.
    ///
    /// Don't call back into this same instance (`mutate`, `read`-backed members like `count`/`elements`,
    /// a subscript, or any other shape member) from within `body` — the lock is already
    /// held, and re-entry traps deterministically under either mechanism instead of hanging:
    /// natively via `os_unfair_lock` for `.lock`, via `ReentrancyTracker` for `.readerWriterLock`.
    ///
    /// Nesting a *different* instance's access inside `body` is fine on its own (`a.mutate { b.mutate { ... } }`
    /// works — reentrancy detection is per-instance) but two instances nested in opposite order on two
    /// threads deadlock, with no trap: thread 1 running `a.mutate { b.mutate { ... } }` while thread 2 runs
    /// `b.mutate { a.mutate { ... } }` can leave each thread holding one lock and waiting on the other,
    /// forever. This can't be caught at compile time or cheaply at runtime, so avoid nesting accesses to
    /// different instances; if you must, always nest in the same global order, or better, snapshot one
    /// first (`let bValue = b.wrappedValue`) and `mutate` the other on its own. Actor types' `mutate`
    /// can't deadlock this way — its closure is synchronous, so it can't `await` into another actor.
    @inlinable
    public func mutate<T: Sendable>(_ body: @Sendable (inout Value) throws -> T) rethrows -> T {
        try write(body)
    }
}
