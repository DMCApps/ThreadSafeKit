/// Deliberately not `Codable`: `Encodable.encode(to:)` is synchronous, but reading
/// isolated actor state requires `await`, so no `encode(to:)` can call ``dictionary``.
/// `init(from:)` could be implemented (actor initializers aren't async), but doing so
/// alone would give asymmetric, surprising conformance, so it's left out too.
/// To (de)serialize, snapshot/restore manually at the call site: encode `await dictionary`,
/// decode into `ThreadSafeDictionary(_:)`.
public actor ThreadSafeDictionary<Key: Hashable & Sendable, Value: Sendable> {
    private var storage: [Key: Value]

    public init(_ dictionary: [Key: Value] = [:]) {
        storage = dictionary
    }

    public var count: Int {
        storage.count
    }

    public var isEmpty: Bool {
        storage.isEmpty
    }

    public var dictionary: [Key: Value] {
        storage
    }

    public var keys: [Key] {
        Array(storage.keys)
    }

    public var values: [Value] {
        Array(storage.values)
    }

    public func getValue(forKey key: Key) -> Value? {
        storage[key]
    }

    public func setValue(_ value: Value?, forKey key: Key) {
        storage[key] = value
    }

    @discardableResult
    public func removeValue(forKey key: Key) -> Value? {
        storage.removeValue(forKey: key)
    }

    @discardableResult
    public func updateValue(_ value: Value, forKey key: Key) -> Value? {
        storage.updateValue(value, forKey: key)
    }

    public func removeAll(keepingCapacity keepCapacity: Bool = false) {
        storage.removeAll(keepingCapacity: keepCapacity)
    }

    public func merge(_ other: [Key: Value], uniquingKeysWith combine: @Sendable (Value, Value) throws -> Value) rethrows {
        try storage.merge(other, uniquingKeysWith: combine)
    }

    public func mapValues<T: Sendable>(_ transform: @Sendable (Value) throws -> T) rethrows -> [Key: T] {
        try storage.mapValues(transform)
    }

    public func compactMapValues<T: Sendable>(_ transform: @Sendable (Value) throws -> T?) rethrows -> [Key: T] {
        try storage.compactMapValues(transform)
    }

    public func filter(_ isIncluded: @Sendable ((key: Key, value: Value)) throws -> Bool) rethrows -> [Key: Value] {
        try storage.filter(isIncluded)
    }

    public func contains(where predicate: @Sendable ((key: Key, value: Value)) throws -> Bool) rethrows -> Bool {
        try storage.contains(where: predicate)
    }

    public func forEach(_ body: @Sendable ((key: Key, value: Value)) throws -> Void) rethrows {
        try storage.forEach(body)
    }

    public func reduce<Result: Sendable>(
        into initial: Result,
        _ updateAccumulatingResult: @Sendable (inout Result, (key: Key, value: Value)) throws -> Void
    ) rethrows -> Result {
        try storage.reduce(into: initial, updateAccumulatingResult)
    }

    public subscript(key: Key) -> Value? {
        storage[key]
    }

    /// Runs `body` as a single unit of work isolated to this actor, so compound
    /// operations (check-then-act, multi-step updates) are atomic — not just each individual call.
    public func mutate<T>(_ body: (inout [Key: Value]) throws -> T) rethrows -> T {
        try body(&storage)
    }
}
