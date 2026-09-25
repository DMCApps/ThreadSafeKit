/// Structural stand-in for `Dictionary` so keyed members can be generic; public only because public signatures use it.
public protocol _ThreadSafeKeyedStorage {
    associatedtype Key: Hashable
    associatedtype KeyedValue
    associatedtype Keys: Collection where Keys.Element == Key
    associatedtype Values: Collection where Values.Element == KeyedValue
    init()
    var keys: Keys { get }
    var values: Values { get }
    subscript(key: Key) -> KeyedValue? { get set }
    mutating func removeValue(forKey key: Key) -> KeyedValue?
    mutating func removeAll(keepingCapacity keepCapacity: Bool)
    mutating func merge(_ other: Self, uniquingKeysWith combine: (KeyedValue, KeyedValue) throws -> KeyedValue) rethrows
    @discardableResult
    mutating func updateValue(_ value: KeyedValue, forKey key: Key) -> KeyedValue?
}

extension Dictionary: _ThreadSafeKeyedStorage {
    public typealias KeyedValue = Value
}

extension ThreadSafe
where Value: _ThreadSafeKeyedStorage, Value.Key: Sendable, Value.KeyedValue: Sendable, Value.Keys: Sendable, Value.Values: Sendable {
    @inlinable
    public convenience init(mechanism: ThreadSafeMechanism = .lock) {
        self.init(wrappedValue: Value(), mechanism: mechanism)
    }

    @inlinable
    public var dictionary: Value { read { $0 } }

    @inlinable
    public var keys: Value.Keys { read { $0.keys } }

    @inlinable
    public var values: Value.Values { read { $0.values } }

    @discardableResult
    @inlinable
    public func removeValue(forKey key: Value.Key) -> Value.KeyedValue? {
        write { $0.removeValue(forKey: key) }
    }

    @discardableResult
    @inlinable
    public func updateValue(_ value: Value.KeyedValue, forKey key: Value.Key) -> Value.KeyedValue? {
        write { $0.updateValue(value, forKey: key) }
    }

    @inlinable
    public func removeAll(keepingCapacity keepCapacity: Bool = false) {
        write { $0.removeAll(keepingCapacity: keepCapacity) }
    }

    @inlinable
    public func merge(
        _ other: Value,
        uniquingKeysWith combine: @Sendable (Value.KeyedValue, Value.KeyedValue) throws -> Value.KeyedValue
    ) rethrows {
        try write { try $0.merge(other, uniquingKeysWith: combine) }
    }

    /// Atomic across the whole get-modify-set, so `dict[k]! += 1` is safe but `dict[k] = dict[k]! + 1` is not.
    @inlinable
    public subscript(key: Value.Key) -> Value.KeyedValue? {
        get { read { $0[key] } }
        _modify {
            beginModify()
            defer { endModify() }
            yield &storage[key]
        }
    }
}

// These don't generalize to `_ThreadSafeKeyedStorage`, so they're constrained to concrete `Dictionary`.
extension ThreadSafe {
    @inlinable
    public func mapValues<Key: Hashable & Sendable, KeyedValue: Sendable, T: Sendable>(
        _ transform: @Sendable (KeyedValue) throws -> T
    ) rethrows -> [Key: T] where Value == [Key: KeyedValue] {
        try read { try $0.mapValues(transform) }
    }

    @inlinable
    public func compactMapValues<Key: Hashable & Sendable, KeyedValue: Sendable, T: Sendable>(
        _ transform: @Sendable (KeyedValue) throws -> T?
    ) rethrows -> [Key: T] where Value == [Key: KeyedValue] {
        try read { try $0.compactMapValues(transform) }
    }

    @inlinable
    public func filter<Key: Hashable & Sendable, KeyedValue: Sendable>(
        _ isIncluded: @Sendable ((key: Key, value: KeyedValue)) throws -> Bool
    ) rethrows -> [Key: KeyedValue] where Value == [Key: KeyedValue] {
        try read { try $0.filter(isIncluded) }
    }

    @inlinable
    public func reserveCapacity<Key: Hashable & Sendable, KeyedValue: Sendable>(
        _ minimumCapacity: Int
    ) where Value == [Key: KeyedValue] {
        write { $0.reserveCapacity(minimumCapacity) }
    }

    @inlinable
    public func popFirst<Key: Hashable & Sendable, KeyedValue: Sendable>() -> (key: Key, value: KeyedValue)?
    where Value == [Key: KeyedValue] {
        write { $0.popFirst() }
    }

    /// Sequence-of-pairs overload; never ambiguous with the `Dictionary` one since the element tuple labels differ.
    @inlinable
    public func merge<Key: Hashable & Sendable, KeyedValue: Sendable>(
        _ other: some Sequence<(Key, KeyedValue)> & Sendable,
        uniquingKeysWith combine: @Sendable (KeyedValue, KeyedValue) throws -> KeyedValue
    ) rethrows where Value == [Key: KeyedValue] {
        try write { try $0.merge(other, uniquingKeysWith: combine) }
    }

    /// Atomic across the whole get-modify-set, so `d[k, default: 0] += 1` is safe.
    @inlinable
    public subscript<Key: Hashable & Sendable, KeyedValue: Sendable>(
        key: Key, default defaultValue: @autoclosure () -> KeyedValue
    ) -> KeyedValue where Value == [Key: KeyedValue] {
        get { read { $0[key] } ?? defaultValue() }
        _modify {
            beginModify()
            defer { endModify() }
            yield &storage[key, default: defaultValue()]
        }
    }
}
