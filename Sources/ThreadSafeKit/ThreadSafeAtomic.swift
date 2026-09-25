/// Actor-backed single-value wrapper. Access requires `await`, matching ``ThreadSafeArray``/``ThreadSafeDictionary``.
///
/// `mutate` comes from `_ThreadSafeActorStorage`'s protocol extension — see that type's doc comment
/// for the `final`/`@inlinable`/`_storage` rationale shared by all four actor types.
public final actor ThreadSafeAtomic<Value: Sendable>: _ThreadSafeActorStorage {
    public var _storage: Value

    @inlinable
    public init(_ value: Value) {
        _storage = value
    }

    @inlinable
    public func get() -> Value {
        _storage
    }

    @available(*, unavailable, message: "Direct assignment isn't atomic across read-modify-write; use mutate(_:) instead")
    @inlinable
    public func set(_ newValue: Value) {
        _storage = newValue
    }
}
