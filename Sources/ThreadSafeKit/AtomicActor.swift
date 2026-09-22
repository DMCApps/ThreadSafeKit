/// Actor-backed alternative to ``Atomic``. Access requires `await`, matching ``ArrayActor``/``DictionaryActor``.
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
