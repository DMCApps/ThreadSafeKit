/// Structural stand-in for `Dictionary` so keyed members can be generic; public only because public signatures use it.
public protocol _ThreadSafeKeyedStorage: Collection where Element == (key: Key, value: KeyedValue) {
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
    func mapValues<T>(_ transform: (KeyedValue) throws -> T) rethrows -> [Key: T]
    func compactMapValues<T>(_ transform: (KeyedValue) throws -> T?) rethrows -> [Key: T]
    func filter(_ isIncluded: (Element) throws -> Bool) rethrows -> [Key: KeyedValue]
    mutating func reserveCapacity(_ minimumCapacity: Int)
    mutating func popFirst() -> Element?
    mutating func merge<S: Sequence>(
        _ other: S, uniquingKeysWith combine: (KeyedValue, KeyedValue) throws -> KeyedValue
    ) rethrows where S.Element == (Key, KeyedValue)
    subscript(key: Key, default defaultValue: @autoclosure () -> KeyedValue) -> KeyedValue { get set }
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

    @inlinable
    public func mapValues<T: Sendable>(_ transform: @Sendable (Value.KeyedValue) throws -> T) rethrows -> [Value.Key: T] {
        try read { try $0.mapValues(transform) }
    }

    @inlinable
    public func compactMapValues<T: Sendable>(_ transform: @Sendable (Value.KeyedValue) throws -> T?) rethrows -> [Value.Key: T] {
        try read { try $0.compactMapValues(transform) }
    }

    @inlinable
    public func filter(_ isIncluded: @Sendable (Value.Element) throws -> Bool) rethrows -> [Value.Key: Value.KeyedValue] {
        try read { try $0.filter(isIncluded) }
    }

    @inlinable
    public func reserveCapacity(_ minimumCapacity: Int) {
        write { $0.reserveCapacity(minimumCapacity) }
    }

    @inlinable
    public func popFirst() -> Value.Element? {
        write { $0.popFirst() }
    }

    /// Sequence-of-pairs overload; never ambiguous with the `Dictionary` one since the element tuple labels differ.
    @inlinable
    public func merge(
        _ other: some Sequence<(Value.Key, Value.KeyedValue)> & Sendable,
        uniquingKeysWith combine: @Sendable (Value.KeyedValue, Value.KeyedValue) throws -> Value.KeyedValue
    ) rethrows {
        try write { try $0.merge(other, uniquingKeysWith: combine) }
    }

    /// Atomic across the whole get-modify-set, so `d[k, default: 0] += 1` is safe.
    @inlinable
    public subscript(key: Value.Key, default defaultValue: @autoclosure () -> Value.KeyedValue) -> Value.KeyedValue {
        get { read { $0[key] } ?? defaultValue() }
        _modify {
            beginModify()
            defer { endModify() }
            yield &storage[key, default: defaultValue()]
        }
    }
}
