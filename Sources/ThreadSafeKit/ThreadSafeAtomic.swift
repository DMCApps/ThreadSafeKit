import Foundation
import os

/// Lock/queue-backed alternative to ``AtomicActor``. Pick the backing mechanism via ``ThreadSafeMechanism``;
/// defaults to a serial `DispatchQueue`.
@propertyWrapper
public final class ThreadSafeAtomic<Value: Sendable>: @unchecked Sendable {
    private enum Backing {
        case lock(OSAllocatedUnfairLock<Value>)
        case queue(DispatchQueue)
    }

    private let backing: Backing
    // Only used by the `.queue` mechanism — the `.lock` mechanism keeps its state inside the
    // `OSAllocatedUnfairLock` instead, and only ever touches this through `wrappedValue`/`mutate`.
    private var storage: Value

    public init(wrappedValue: Value, mechanism: ThreadSafeMechanism = .dispatchQueue) {
        switch mechanism {
        case .lock:
            backing = .lock(OSAllocatedUnfairLock(initialState: wrappedValue))
            storage = wrappedValue
        case .dispatchQueue:
            backing = .queue(DispatchQueue(label: "com.threadsafekit.atomic"))
            storage = wrappedValue
        }
    }

    public var wrappedValue: Value {
        get {
            switch backing {
            case .lock(let lock):
                return lock.withLock { $0 }
            case .queue(let queue):
                return queue.sync { storage }
            }
        }
        @available(*, unavailable, message: "Direct assignment isn't atomic across read-modify-write; use mutate(_:) instead")
        set {
            switch backing {
            case .lock(let lock):
                lock.withLock { $0 = newValue }
            case .queue(let queue):
                queue.sync { storage = newValue }
            }
        }
    }

    public func mutate(_ mutation: @Sendable (inout Value) -> Void) {
        switch backing {
        case .lock(let lock):
            lock.withLock(mutation)
        case .queue(let queue):
            queue.sync { mutation(&storage) }
        }
    }
}

extension ThreadSafeAtomic: CustomStringConvertible {
    public var description: String {
        "ThreadSafeAtomic(\(wrappedValue))"
    }
}

extension ThreadSafeAtomic: Equatable where Value: Equatable {
    public static func == (lhs: ThreadSafeAtomic, rhs: ThreadSafeAtomic) -> Bool {
        lhs.wrappedValue == rhs.wrappedValue
    }
}

extension ThreadSafeAtomic: Hashable where Value: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(wrappedValue)
    }
}

extension ThreadSafeAtomic: Codable where Value: Codable {
    public convenience init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(wrappedValue: try container.decode(Value.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}
