/// Structural stand-in for `Dictionary` so the keyed-storage extension below can be written generically.
/// Public only because it must appear in public extension signatures — not intended for outside conformance.
public protocol _ThreadSafeKeyedStorage {
    associatedtype Key: Hashable
    associatedtype KeyedValue
    init()
    subscript(key: Key) -> KeyedValue? { get set }
    mutating func removeValue(forKey key: Key) -> KeyedValue?
    mutating func removeAll(keepingCapacity keepCapacity: Bool)
    mutating func merge(_ other: Self, uniquingKeysWith combine: (KeyedValue, KeyedValue) throws -> KeyedValue) rethrows
}

extension Dictionary: _ThreadSafeKeyedStorage {}

extension ThreadSafe where Value: _ThreadSafeKeyedStorage, Value.Key: Sendable, Value.KeyedValue: Sendable {
    public convenience init(mechanism: ThreadSafeMechanism = .dispatchQueue) {
        self.init(wrappedValue: Value(), mechanism: mechanism)
    }

    public var dictionary: Value { read { $0 } }

    public func getValue(forKey key: Value.Key) -> Value.KeyedValue? {
        read { $0[key] }
    }

    public func setValue(_ value: Value.KeyedValue?, forKey key: Value.Key) {
        write { $0[key] = value }
    }

    @discardableResult
    public func removeValue(forKey key: Value.Key) -> Value.KeyedValue? {
        write { $0.removeValue(forKey: key) }
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

    public subscript(key: Value.Key) -> Value.KeyedValue? {
        get { read { $0[key] } }
        set { write { $0[key] = newValue } }
    }
}
