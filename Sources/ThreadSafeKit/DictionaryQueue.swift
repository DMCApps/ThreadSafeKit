import Foundation

/// DispatchQueue-backed alternative to ``DictionaryActor``.
/// Uses a concurrent queue with barrier writes: reads run in parallel, writes are exclusive.
public final class DictionaryQueue<Key: Hashable & Sendable, Value: Sendable>: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.threadsafekit.dictionaryqueue", attributes: .concurrent)
    private var storage: [Key: Value]

    public init(_ dictionary: [Key: Value] = [:]) {
        storage = dictionary
    }

    public var count: Int {
        queue.sync { storage.count }
    }

    public var isEmpty: Bool {
        queue.sync { storage.isEmpty }
    }

    public var dictionary: [Key: Value] {
        queue.sync { storage }
    }

    public func getValue(forKey key: Key) -> Value? {
        queue.sync { storage[key] }
    }

    public func setValue(_ value: Value?, forKey key: Key) {
        queue.sync(flags: .barrier) {
            storage[key] = value
        }
    }

    @discardableResult
    public func removeValue(forKey key: Key) -> Value? {
        queue.sync(flags: .barrier) {
            storage.removeValue(forKey: key)
        }
    }

    public func removeAll(keepingCapacity keepCapacity: Bool = false) {
        queue.sync(flags: .barrier) {
            storage.removeAll(keepingCapacity: keepCapacity)
        }
    }

    public func merge(_ other: [Key: Value], uniquingKeysWith combine: (Value, Value) throws -> Value) rethrows {
        try queue.sync(flags: .barrier) {
            try storage.merge(other, uniquingKeysWith: combine)
        }
    }

    public func forEach(_ body: ((key: Key, value: Value)) throws -> Void) rethrows {
        try queue.sync { try storage.forEach(body) }
    }

    public func reduce<Result>(
        into initial: Result,
        _ updateAccumulatingResult: (inout Result, (key: Key, value: Value)) throws -> Void
    ) rethrows -> Result {
        try queue.sync { try storage.reduce(into: initial, updateAccumulatingResult) }
    }

    public subscript(key: Key) -> Value? {
        get { queue.sync { storage[key] } }
        set { queue.sync(flags: .barrier) { storage[key] = newValue } }
    }

    /// Runs `body` as a single unit of work under the write lock, so compound
    /// operations (check-then-act, multi-step updates) are atomic — not just each individual call.
    public func mutate<T>(_ body: (inout [Key: Value]) throws -> T) rethrows -> T {
        try queue.sync(flags: .barrier) { try body(&storage) }
    }
}

extension DictionaryQueue: Codable where Key: Codable, Value: Codable {
    public convenience init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(try container.decode([Key: Value].self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(dictionary)
    }
}
