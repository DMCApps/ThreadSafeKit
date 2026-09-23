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

extension Atomic: Equatable where Value: Equatable {
    public static func == (lhs: Atomic, rhs: Atomic) -> Bool {
        lhs.wrappedValue == rhs.wrappedValue
    }
}

extension Atomic: Codable where Value: Codable {
    public convenience init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(wrappedValue: try container.decode(Value.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}
