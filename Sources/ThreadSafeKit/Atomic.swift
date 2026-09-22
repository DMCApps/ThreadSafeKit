import os

@propertyWrapper
public final class Atomic<Value: Sendable>: Sendable {
    private let lock: OSAllocatedUnfairLock<Value>

    public init(wrappedValue: Value) {
        lock = OSAllocatedUnfairLock(initialState: wrappedValue)
    }

    public var wrappedValue: Value {
        get { lock.withLock { $0 } }
        @available(*, unavailable, message: "Direct assignment isn't atomic across read-modify-write; use mutate(_:) instead")
        set { lock.withLock { $0 = newValue } }
    }

    public func mutate(_ mutation: @Sendable (inout Value) -> Void) {
        lock.withLock(mutation)
    }
}
