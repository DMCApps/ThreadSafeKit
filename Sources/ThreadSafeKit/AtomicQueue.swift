import Foundation

/// DispatchQueue-backed alternative to ``Atomic``, using a serial queue instead of a lock.
@propertyWrapper
public final class AtomicQueue<Value: Sendable>: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.threadsafekit.atomicqueue")
    private var value: Value

    public init(wrappedValue: Value) {
        value = wrappedValue
    }

    public var wrappedValue: Value {
        get { queue.sync { value } }
        set { queue.sync { value = newValue } }
    }

    public func mutate(_ mutation: (inout Value) -> Void) {
        queue.sync { mutation(&value) }
    }
}
