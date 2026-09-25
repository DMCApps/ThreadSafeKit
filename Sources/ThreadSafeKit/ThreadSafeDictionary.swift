/// `mutate` and the read-only `Collection` members (`Storage.Element == (key: Key, value: Value)`)
/// come from `_ThreadSafeActorStorage`'s protocol extension — see that type's doc comment for the
/// `final`/`@inlinable`/`_storage` rationale shared by all four actor types.
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

    /// The sequence-of-pairs overload, alongside the whole-dictionary one above.
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

    /// `d[k, default: 0] += 1` isn't expressible here — an actor's subscript can't be assigned or
    /// modified from outside the actor, so this is get-only, mirroring `subscript(key:)` above.
    /// For an atomic default-and-update, use `mutate`: `await dict.mutate { $0[k, default: 0] += 1 }`.
    @inlinable
    public subscript(key: Key, default defaultValue: @autoclosure @Sendable () -> Value) -> Value {
        _storage[key, default: defaultValue()]
    }
}
