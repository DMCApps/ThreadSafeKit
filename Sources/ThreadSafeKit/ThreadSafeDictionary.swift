import Foundation
import os

/// Lock/queue-backed alternative to ``DictionaryActor``. Pick the backing mechanism via ``ThreadSafeMechanism``;
/// defaults to a concurrent `DispatchQueue` with barrier writes (reads run in parallel, writes are exclusive).
public final class ThreadSafeDictionary<Key: Hashable & Sendable, Value: Sendable>: @unchecked Sendable {
    private final class Box<T> {
        var value: T
        init(_ value: T) { self.value = value }
    }

    private enum Backing {
        case lock(OSAllocatedUnfairLock<[Key: Value]>)
        case queue(DispatchQueue, Box<[Key: Value]>)
    }

    private let backing: Backing

    public init(_ dictionary: [Key: Value] = [:], mechanism: ThreadSafeMechanism = .dispatchQueue) {
        switch mechanism {
        case .lock:
            backing = .lock(OSAllocatedUnfairLock(initialState: dictionary))
        case .dispatchQueue:
            backing = .queue(DispatchQueue(label: "com.threadsafekit.dictionary", attributes: .concurrent), Box(dictionary))
        }
    }

    private func read<T: Sendable>(_ body: @Sendable (inout [Key: Value]) throws -> T) rethrows -> T {
        switch backing {
        case .lock(let lock):
            return try lock.withLock(body)
        case .queue(let queue, let box):
            return try queue.sync { try body(&box.value) }
        }
    }

    private func write<T: Sendable>(_ body: @Sendable (inout [Key: Value]) throws -> T) rethrows -> T {
        switch backing {
        case .lock(let lock):
            return try lock.withLock(body)
        case .queue(let queue, let box):
            return try queue.sync(flags: .barrier) { try body(&box.value) }
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

// Dictionary itself has no Hashable conformance in the standard library (even when
// Value: Hashable), since combining key/value hashes has to be order-independent.
// XOR each entry's combined hash so iteration order doesn't affect the result.
extension ThreadSafeDictionary: Hashable where Value: Hashable {
    public func hash(into hasher: inout Hasher) {
        let combined = dictionary.reduce(into: 0) { result, entry in
            var entryHasher = Hasher()
            entryHasher.combine(entry.key)
            entryHasher.combine(entry.value)
            result ^= entryHasher.finalize()
        }
        hasher.combine(combined)
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
