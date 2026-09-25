/// Actor-backed single-value wrapper. Access requires `await`, matching ``ThreadSafeArray``/``ThreadSafeDictionary``.
///
/// `final`: Swift doesn't treat actors as implicitly `final`, and calling a non-final actor's method
/// through a captured instance (e.g. inside a `@Sendable` closure passed to a `Task`) compiles to a
/// vtable call, which the compiler can't specialize/inline even when the callee is `@inlinable`. This
/// type is `final` specifically so that call can be devirtualized and inlined into the caller — don't
/// remove it. Every public member is `@inlinable` for the same reason `ThreadSafe`'s are (see the
/// comment at the top of `ThreadSafe.swift`): so a client module can specialize the call for its
/// concrete `Value` instead of paying for unspecialized generic dispatch. `value` is
/// `@usableFromInline` so those inlinable bodies can reach it — don't make it `private` again. Mark
/// any new public member `@inlinable` too.
public final actor ThreadSafeAtomic<Value: Sendable> {
    @usableFromInline
    var value: Value

    @inlinable
    public init(_ value: Value) {
        self.value = value
    }

    @inlinable
    public func get() -> Value {
        value
    }

    @available(*, unavailable, message: "Direct assignment isn't atomic across read-modify-write; use mutate(_:) instead")
    @inlinable
    public func set(_ newValue: Value) {
        value = newValue
    }

    /// Runs `body` as a single unit of work isolated to this actor, so compound
    /// operations (check-then-act, read-and-update) are atomic, not just each individual call.
    @inlinable
    public func mutate<T>(_ body: (inout Value) throws -> T) rethrows -> T {
        try body(&value)
    }
}
