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
    public convenience init(mechanism: ThreadSafeMechanism = .readerWriterLock) {
        self.init(wrappedValue: Value(), mechanism: mechanism)
    }

    public var dictionary: Value { read { $0 } }

    public var keys: Value.Keys { read { $0.keys } }

    public var values: Value.Values { read { $0.values } }

    @discardableResult
    public func removeValue(forKey key: Value.Key) -> Value.KeyedValue? {
        write { $0.removeValue(forKey: key) }
    }

    @discardableResult
    public func updateValue(_ value: Value.KeyedValue, forKey key: Value.Key) -> Value.KeyedValue? {
        write { $0.updateValue(value, forKey: key) }
    }

    public func removeAll(keepingCapacity keepCapacity: Bool = false) {
        write { $0.removeAll(keepingCapacity: keepCapacity) }
    }

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
    public subscript(key: Value.Key) -> Value.KeyedValue? {
        get { read { $0[key] } }
        _modify {
            beginModify()
            defer { endModify() }
            yield &storage[key]
        }
    }
}

// `mapValues`/`compactMapValues`/`filter`/`contains(where:)` change the value type or return a plain
// dictionary/bool, rather than generalizing to arbitrary keyed storage — kept off
// `_ThreadSafeKeyedStorage` (per its doc comment) and constrained directly to the concrete `Dictionary`
// shape instead.
extension ThreadSafe {
    public func mapValues<Key: Hashable & Sendable, KeyedValue: Sendable, T: Sendable>(
        _ transform: @Sendable (KeyedValue) throws -> T
    ) rethrows -> [Key: T] where Value == [Key: KeyedValue] {
        try read { try $0.mapValues(transform) }
    }

    public func compactMapValues<Key: Hashable & Sendable, KeyedValue: Sendable, T: Sendable>(
        _ transform: @Sendable (KeyedValue) throws -> T?
    ) rethrows -> [Key: T] where Value == [Key: KeyedValue] {
        try read { try $0.compactMapValues(transform) }
    }

    public func filter<Key: Hashable & Sendable, KeyedValue: Sendable>(
        _ isIncluded: @Sendable ((key: Key, value: KeyedValue)) throws -> Bool
    ) rethrows -> [Key: KeyedValue] where Value == [Key: KeyedValue] {
        try read { try $0.filter(isIncluded) }
    }

    public func contains<Key: Hashable & Sendable, KeyedValue: Sendable>(
        where predicate: @Sendable ((key: Key, value: KeyedValue)) throws -> Bool
    ) rethrows -> Bool where Value == [Key: KeyedValue] {
        try read { try $0.contains(where: predicate) }
    }
}
