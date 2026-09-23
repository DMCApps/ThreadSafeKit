import Foundation
import os

/// Lock/queue-backed alternative to ``DictionaryActor``. Pick the backing mechanism via ``ThreadSafeMechanism``;
/// defaults to a concurrent `DispatchQueue` with barrier writes (reads run in parallel, writes are exclusive).
///
/// Also usable as a property wrapper: `wrappedValue` is a plain-dictionary snapshot (read-only — direct
/// assignment isn't atomic across read-modify-write), and `projectedValue` is this instance itself, so
/// `$name` gives `setValue`/`mutate`/subscript/etc.
@propertyWrapper
public final class ThreadSafeDictionary<Key: Hashable & Sendable, Value: Sendable>: @unchecked Sendable {
    private enum Backing {
        case lock(OSAllocatedUnfairLock<[Key: Value]>)
        case queue(DispatchQueue)
    }

    private let backing: Backing
    // Only used by the `.queue` mechanism — the `.lock` mechanism keeps its state inside the
    // `OSAllocatedUnfairLock` instead, and only ever touches this through `read`/`write`.
    private var storage: [Key: Value]

    public init(_ dictionary: [Key: Value] = [:], mechanism: ThreadSafeMechanism = .dispatchQueue) {
        switch mechanism {
        case .lock:
            backing = .lock(OSAllocatedUnfairLock(initialState: dictionary))
            storage = [:]
        case .dispatchQueue:
            backing = .queue(DispatchQueue(label: "com.threadsafekit.dictionary", attributes: .concurrent))
            storage = dictionary
        }
    }

    public convenience init(wrappedValue: [Key: Value], mechanism: ThreadSafeMechanism = .dispatchQueue) {
        self.init(wrappedValue, mechanism: mechanism)
    }

    private func read<T: Sendable>(_ body: @Sendable (inout [Key: Value]) throws -> T) rethrows -> T {
        switch backing {
        case .lock(let lock):
            return try lock.withLock(body)
        case .queue(let queue):
            return try queue.sync { try body(&storage) }
        }
    }

    private func write<T: Sendable>(_ body: @Sendable (inout [Key: Value]) throws -> T) rethrows -> T {
        switch backing {
        case .lock(let lock):
            return try lock.withLock(body)
        case .queue(let queue):
            return try queue.sync(flags: .barrier) { try body(&storage) }
        }
    }

    public var count: Int {
        read { $0.count }
    }

    public var isEmpty: Bool {
        read { $0.isEmpty }
    }

    public var dictionary: [Key: Value] {
        read { $0 }
    }

    public var wrappedValue: [Key: Value] {
        get { dictionary }
        @available(*, unavailable, message: "Direct assignment isn't atomic across read-modify-write; use $name's setValue/mutate/etc. instead")
        set {}
    }

    public var projectedValue: ThreadSafeDictionary<Key, Value> {
        self
    }

    public func getValue(forKey key: Key) -> Value? {
        read { $0[key] }
    }

    public func setValue(_ value: Value?, forKey key: Key) {
        write { $0[key] = value }
    }

    @discardableResult
    public func removeValue(forKey key: Key) -> Value? {
        write { $0.removeValue(forKey: key) }
    }

    public func removeAll(keepingCapacity keepCapacity: Bool = false) {
        write { $0.removeAll(keepingCapacity: keepCapacity) }
    }

    public func merge(_ other: [Key: Value], uniquingKeysWith combine: @Sendable (Value, Value) throws -> Value) rethrows {
        try write { try $0.merge(other, uniquingKeysWith: combine) }
    }

    public func forEach(_ body: @Sendable ((key: Key, value: Value)) throws -> Void) rethrows {
        try read { try $0.forEach(body) }
    }

    public func reduce<Result: Sendable>(
        into initial: Result,
        _ updateAccumulatingResult: @Sendable (inout Result, (key: Key, value: Value)) throws -> Void
    ) rethrows -> Result {
        try read { try $0.reduce(into: initial, updateAccumulatingResult) }
    }

    public subscript(key: Key) -> Value? {
        get { read { $0[key] } }
        set { write { $0[key] = newValue } }
    }

    /// Runs `body` as a single unit of work under the lock/queue, so compound
    /// operations (check-then-act, multi-step updates) are atomic — not just each individual call.
    public func mutate<T: Sendable>(_ body: @Sendable (inout [Key: Value]) throws -> T) rethrows -> T {
        try write(body)
    }
}

extension ThreadSafeDictionary: CustomStringConvertible {
    public var description: String {
        "ThreadSafeDictionary(\(dictionary))"
    }
}

extension ThreadSafeDictionary: Equatable where Value: Equatable {
    public static func == (lhs: ThreadSafeDictionary, rhs: ThreadSafeDictionary) -> Bool {
        lhs.dictionary == rhs.dictionary
    }
}

// Dictionary itself is Hashable where Value: Hashable, and hashes order-independently.
extension ThreadSafeDictionary: Hashable where Value: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(dictionary)
    }
}

extension ThreadSafeDictionary: Codable where Key: Codable, Value: Codable {
    public convenience init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(try container.decode([Key: Value].self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(dictionary)
    }
}
