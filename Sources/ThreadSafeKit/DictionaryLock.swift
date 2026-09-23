import os

/// Lock-backed alternative to ``DictionaryActor``, using `OSAllocatedUnfairLock` instead of an actor.
public final class DictionaryLock<Key: Hashable & Sendable, Value: Sendable>: Sendable {
    private let lock: OSAllocatedUnfairLock<[Key: Value]>

    public init(_ dictionary: [Key: Value] = [:]) {
        lock = OSAllocatedUnfairLock(initialState: dictionary)
    }

    public var count: Int {
        lock.withLock { $0.count }
    }

    public var isEmpty: Bool {
        lock.withLock { $0.isEmpty }
    }

    public var dictionary: [Key: Value] {
        lock.withLock { $0 }
    }

    public func getValue(forKey key: Key) -> Value? {
        lock.withLock { $0[key] }
    }

    public func setValue(_ value: Value?, forKey key: Key) {
        lock.withLock { $0[key] = value }
    }

    @discardableResult
    public func removeValue(forKey key: Key) -> Value? {
        lock.withLock { $0.removeValue(forKey: key) }
    }

    public func removeAll(keepingCapacity keepCapacity: Bool = false) {
        lock.withLock { $0.removeAll(keepingCapacity: keepCapacity) }
    }

    public func merge(_ other: [Key: Value], uniquingKeysWith combine: @Sendable (Value, Value) throws -> Value) rethrows {
        try lock.withLock { try $0.merge(other, uniquingKeysWith: combine) }
    }

    public func forEach(_ body: @Sendable ((key: Key, value: Value)) throws -> Void) rethrows {
        try lock.withLock { try $0.forEach(body) }
    }

    public func reduce<Result: Sendable>(
        into initial: Result,
        _ updateAccumulatingResult: @Sendable (inout Result, (key: Key, value: Value)) throws -> Void
    ) rethrows -> Result {
        try lock.withLock { try $0.reduce(into: initial, updateAccumulatingResult) }
    }

    public subscript(key: Key) -> Value? {
        get { lock.withLock { $0[key] } }
        set { lock.withLock { $0[key] = newValue } }
    }

    /// Runs `body` as a single unit of work under the lock, so compound
    /// operations (check-then-act, multi-step updates) are atomic — not just each individual call.
    public func mutate<T: Sendable>(_ body: @Sendable (inout [Key: Value]) throws -> T) rethrows -> T {
        try lock.withLock(body)
    }
}

extension DictionaryLock: CustomStringConvertible {
    public var description: String {
        "DictionaryLock(\(dictionary))"
    }
}

extension DictionaryLock: Equatable where Value: Equatable {
    public static func == (lhs: DictionaryLock, rhs: DictionaryLock) -> Bool {
        lhs.dictionary == rhs.dictionary
    }
}

// Dictionary itself has no Hashable conformance in the standard library (even when
// Value: Hashable), since combining key/value hashes has to be order-independent.
// XOR each entry's combined hash so iteration order doesn't affect the result.
extension DictionaryLock: Hashable where Value: Hashable {
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

extension DictionaryLock: Codable where Key: Codable, Value: Codable {
    public convenience init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(try container.decode([Key: Value].self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(dictionary)
    }
}
