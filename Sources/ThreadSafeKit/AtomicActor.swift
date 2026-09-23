/// Actor-backed alternative to ``Atomic``. Access requires `await`, matching ``ArrayActor``/``DictionaryActor``.
///
/// Deliberately not `Codable`: `Encodable.encode(to:)` is synchronous, but reading
/// isolated actor state requires `await`, so no `encode(to:)` can call ``get()``.
/// `init(from:)` could be implemented (actor initializers aren't async), but doing so
/// alone would give asymmetric, surprising conformance, so it's left out too.
/// To (de)serialize, snapshot/restore manually at the call site: encode `await get()`,
/// decode into `AtomicActor(_:)`.
public actor AtomicActor<Value: Sendable> {
    private var value: Value

    public init(_ value: Value) {
        self.value = value
    }

    public func get() -> Value {
        value
    }

    @available(*, unavailable, message: "Direct assignment isn't atomic across read-modify-write; use mutate(_:) instead")
    public func set(_ newValue: Value) {
        value = newValue
    }

    public func mutate(_ mutation: (inout Value) -> Void) {
        mutation(&value)
    }
}
