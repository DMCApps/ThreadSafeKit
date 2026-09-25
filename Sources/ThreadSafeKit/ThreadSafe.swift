import os
#if canImport(Darwin)
import Darwin
#endif

/// Lock-backed thread-safe wrapper around any `Sendable` value, usable as a property wrapper whose `$name` exposes `mutate`.
@propertyWrapper
public final class ThreadSafe<Value: Sendable>: @unchecked Sendable {
    // Members are `@inlinable` (and actors `final`) so clients can specialize and devirtualize calls; don't remove either.
    @usableFromInline
    enum Backing {
        case lock(OSAllocatedUnfairLock<Void>)
        case readerWriterLock(ReaderWriterLock)
    }

    @usableFromInline
    let backing: Backing
    // Stored outside the lock so `_modify` can yield `&storage` directly; internal because only the lock guards it.
    @usableFromInline
    var storage: Value

    // Traps if a `_modify` yield resumes on another thread, since cross-thread unlock is undefined behavior.
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

    // `.lock` skips `ReentrancyTracker` since `os_unfair_lock` already traps on relock, whereas `pthread_rwlock` would hang.
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

    /// Takes the write lock for a subscript `_modify` to hold across its `yield`; pair with `endModify()`.
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

    /// Only reached under `.readerWriterLock`; `.lock` reentry crashes inside `os_unfair_lock`.
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

    // Snapshots are copies only for value types; reference types return the shared instance.
    @inlinable
    public var wrappedValue: Value {
        get { read { $0 } }
        @available(*, unavailable, message: "Direct assignment isn't atomic across read-modify-write; use $name's mutate/etc. instead")
        set {}
    }

    @inlinable
    public var projectedValue: ThreadSafe<Value> { self }

    /// Runs `body` atomically under the lock; reentering this instance traps, and opposite-order nesting of two instances can deadlock.
    @inlinable
    public func mutate<T: Sendable>(_ body: @Sendable (inout Value) throws -> T) rethrows -> T {
        try write(body)
    }
}
