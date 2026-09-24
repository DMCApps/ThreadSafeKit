/// Actor-backed single-value wrapper. Access requires `await`, matching ``ThreadSafeArray``/``ThreadSafeDictionary``.
///
/// Deliberately not `Codable`: `Encodable.encode(to:)` is synchronous, but reading
/// isolated actor state requires `await`, so no `encode(to:)` can call ``get()``.
/// `init(from:)` could be implemented (actor initializers aren't async), but doing so
/// alone would give asymmetric, surprising conformance, so it's left out too.
/// To (de)serialize, snapshot/restore manually at the call site: encode `await get()`,
/// decode into `ThreadSafeAtomic(_:)`.
public actor ThreadSafeAtomic<Value: Sendable> {
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

    /// Runs `body` as a single unit of work isolated to this actor, so compound
    /// operations (check-then-act, read-and-update) are atomic, not just each individual call.
    public func mutate<T>(_ body: (inout Value) throws -> T) rethrows -> T {
        try body(&value)
    }
}
