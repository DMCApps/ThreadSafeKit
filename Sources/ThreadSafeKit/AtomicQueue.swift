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
        @available(*, unavailable, message: "Direct assignment isn't atomic across read-modify-write; use mutate(_:) instead")
        set { queue.sync { value = newValue } }
    }

    public func mutate(_ mutation: (inout Value) -> Void) {
        queue.sync { mutation(&value) }
    }
}

extension AtomicQueue: Equatable where Value: Equatable {
    public static func == (lhs: AtomicQueue, rhs: AtomicQueue) -> Bool {
        lhs.wrappedValue == rhs.wrappedValue
    }
}

extension AtomicQueue: Codable where Value: Codable {
    public convenience init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(wrappedValue: try container.decode(Value.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}
