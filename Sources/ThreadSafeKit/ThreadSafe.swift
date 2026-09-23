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
    // Only used by the `.queue` mechanism — the `.lock` mechanism keeps its state inside the
    // `OSAllocatedUnfairLock` instead, and only ever touches this through `read`/`write`.
    private var storage: Value

    public init(wrappedValue: Value, mechanism: ThreadSafeMechanism = .dispatchQueue) {
        switch mechanism {
        case .lock:
            backing = .lock(OSAllocatedUnfairLock(initialState: wrappedValue))
            storage = wrappedValue
        case .dispatchQueue:
            backing = .queue(DispatchQueue(label: "com.threadsafekit.\(Value.self)", attributes: .concurrent))
            storage = wrappedValue
        }
    }

    public convenience init(_ value: Value, mechanism: ThreadSafeMechanism = .dispatchQueue) {
        self.init(wrappedValue: value, mechanism: mechanism)
    }

    func read<T: Sendable>(_ body: @Sendable (inout Value) throws -> T) rethrows -> T {
        switch backing {
        case .lock(let lock): return try lock.withLock(body)
        case .queue(let queue): return try queue.sync { try body(&storage) }
        }
    }

    func write<T: Sendable>(_ body: @Sendable (inout Value) throws -> T) rethrows -> T {
        switch backing {
        case .lock(let lock): return try lock.withLock(body)
        case .queue(let queue): return try queue.sync(flags: .barrier) { try body(&storage) }
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
    public func mutate<T: Sendable>(_ body: @Sendable (inout Value) throws -> T) rethrows -> T {
        try write(body)
    }
}
