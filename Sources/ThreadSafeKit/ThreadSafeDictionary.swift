/// Actor-backed dictionary; shared members come from `_ThreadSafeActorStorage`.
public final actor ThreadSafeDictionary<Key: Hashable & Sendable, Value: Sendable>: _ThreadSafeActorStorage {
    public var _storage: [Key: Value]

    @inlinable
    public init(_ dictionary: [Key: Value] = [:]) {
        _storage = dictionary
    }

    @inlinable
    public var dictionary: [Key: Value] {
        _storage
    }

    @inlinable
    public var keys: Dictionary<Key, Value>.Keys {
        _storage.keys
    }

    @inlinable
    public var values: Dictionary<Key, Value>.Values {
        _storage.values
    }

    @discardableResult
    @inlinable
    public func removeValue(forKey key: Key) -> Value? {
        _storage.removeValue(forKey: key)
    }

    @discardableResult
    @inlinable
    public func updateValue(_ value: Value, forKey key: Key) -> Value? {
        _storage.updateValue(value, forKey: key)
    }

    @inlinable
    public func removeAll(keepingCapacity keepCapacity: Bool = false) {
        _storage.removeAll(keepingCapacity: keepCapacity)
    }

    @inlinable
    public func popFirst() -> (key: Key, value: Value)? {
        _storage.popFirst()
    }

    @inlinable
    public func reserveCapacity(_ minimumCapacity: Int) {
        _storage.reserveCapacity(minimumCapacity)
    }

    @inlinable
    public func merge(_ other: [Key: Value], uniquingKeysWith combine: @Sendable (Value, Value) throws -> Value) rethrows {
        try _storage.merge(other, uniquingKeysWith: combine)
    }

    /// Sequence-of-pairs overload.
    @inlinable
    public func merge(
        _ other: some Sequence<(Key, Value)> & Sendable,
        uniquingKeysWith combine: @Sendable (Value, Value) throws -> Value
    ) rethrows {
        try _storage.merge(other, uniquingKeysWith: combine)
    }

    @inlinable
    public func mapValues<T: Sendable>(_ transform: @Sendable (Value) throws -> T) rethrows -> [Key: T] {
        try _storage.mapValues(transform)
    }

    @inlinable
    public func compactMapValues<T: Sendable>(_ transform: @Sendable (Value) throws -> T?) rethrows -> [Key: T] {
        try _storage.compactMapValues(transform)
    }

    @inlinable
    public func filter(_ isIncluded: @Sendable ((key: Key, value: Value)) throws -> Bool) rethrows -> [Key: Value] {
        try _storage.filter(isIncluded)
    }

    @inlinable
    public subscript(key: Key) -> Value? {
        _storage[key]
    }

    /// Get-only since actor subscripts can't be mutated externally; use `mutate` for default-and-update.
    @inlinable
    public subscript(key: Key, default defaultValue: @autoclosure @Sendable () -> Value) -> Value {
        _storage[key, default: defaultValue()]
    }
}
