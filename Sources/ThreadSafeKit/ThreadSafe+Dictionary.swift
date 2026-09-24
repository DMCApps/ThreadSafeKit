/// Structural stand-in for `Dictionary` so the keyed-storage extension below can be written generically.
/// Public only because it must appear in public extension signatures — not intended for outside conformance.
///
/// It exists because computed properties can't be generic: `keys`/`values`/`dictionary` need a
/// `where Value == [K: V]` constraint to express their return types, but a plain constraint like
/// that can't be attached to a protocol extension over an arbitrary keyed-storage shape. Requiring
/// only members `Dictionary` already has — with associated types standing in for `Keys`/`Values` —
/// means the `Dictionary` conformance below adds nothing beyond the required `KeyedValue` typealias.
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
    public convenience init(mechanism: ThreadSafeMechanism = .readerWriterLock) {
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

    /// Atomic for the whole access, including `dict[k]! += 1`, `dict[k]?.append(x)`, and plain
    /// `dict[k] = v`/`dict[k] = nil` (the latter removes the key) — the write lock is held across
    /// the entire get-modify-set. `dict[k] = dict[k]! + 1` is two separate accesses and is NOT
    /// atomic; use `+=` or `mutate` for that.
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

// `mapValues`/`compactMapValues`/`filter`/`reserveCapacity`/`popFirst`/the default subscript/the
// sequence-of-pairs `merge` overload change the value type, return a plain dictionary/tuple, or
// only exist on the concrete type, rather than generalizing to arbitrary keyed storage — kept off
// `_ThreadSafeKeyedStorage` (per its doc comment) and constrained directly to the concrete `Dictionary`
// shape instead.
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

    /// The stdlib's sequence-of-pairs `merge` overload, alongside the whole-dictionary one above.
    /// `some Sequence<(Key, KeyedValue)>` (an unlabeled-tuple `Element`) never matches a `Dictionary`
    /// argument (whose `Element` is the labeled tuple `(key:, value:)`), so this can never collide
    /// with a call passing another dictionary — that always resolves to the overload above instead.
    @inlinable
    public func merge<Key: Hashable & Sendable, KeyedValue: Sendable>(
        _ other: some Sequence<(Key, KeyedValue)> & Sendable,
        uniquingKeysWith combine: @Sendable (KeyedValue, KeyedValue) throws -> KeyedValue
    ) rethrows where Value == [Key: KeyedValue] {
        try write { try $0.merge(other, uniquingKeysWith: combine) }
    }

    /// `d[k, default: 0] += 1` is atomic for the whole access — the write lock is held across the
    /// entire get-modify-set via `_modify`, same as `subscript(key:)` above. `d[k, default: 0] =
    /// d[k, default: 0] + 1` is NOT atomic: that's two separate accesses (a `get`, then a
    /// `_modify`), so another writer can slip in between them.
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
