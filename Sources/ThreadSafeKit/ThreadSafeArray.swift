import Foundation
import os

/// Lock/queue-backed alternative to ``ArrayActor``. Pick the backing mechanism via ``ThreadSafeMechanism``;
/// defaults to a concurrent `DispatchQueue` with barrier writes (reads run in parallel, writes are exclusive).
public final class ThreadSafeArray<Element: Sendable>: @unchecked Sendable {
    private final class Box<T> {
        var value: T
        init(_ value: T) { self.value = value }
    }

    private enum Backing {
        case lock(OSAllocatedUnfairLock<[Element]>)
        case queue(DispatchQueue, Box<[Element]>)
    }

    private let backing: Backing

    public convenience init(mechanism: ThreadSafeMechanism = .dispatchQueue) {
        self.init([], mechanism: mechanism)
    }

    public init(_ elements: some Sequence<Element>, mechanism: ThreadSafeMechanism = .dispatchQueue) {
        let array = Array(elements)
        switch mechanism {
        case .lock:
            backing = .lock(OSAllocatedUnfairLock(initialState: array))
        case .dispatchQueue:
            backing = .queue(DispatchQueue(label: "com.threadsafekit.array", attributes: .concurrent), Box(array))
        }
    }

    private func read<T: Sendable>(_ body: @Sendable (inout [Element]) throws -> T) rethrows -> T {
        switch backing {
        case .lock(let lock):
            return try lock.withLock(body)
        case .queue(let queue, let box):
            return try queue.sync { try body(&box.value) }
        }
    }

    private func write<T: Sendable>(_ body: @Sendable (inout [Element]) throws -> T) rethrows -> T {
        switch backing {
        case .lock(let lock):
            return try lock.withLock(body)
        case .queue(let queue, let box):
            return try queue.sync(flags: .barrier) { try body(&box.value) }
        }
    }

    public var count: Int {
        read { $0.count }
    }

    public var isEmpty: Bool {
        read { $0.isEmpty }
    }

    public var first: Element? {
        read { $0.first }
    }

    public var last: Element? {
        read { $0.last }
    }

    public var elements: [Element] {
        read { $0 }
    }

    public func append(_ newElement: Element) {
        write { $0.append(newElement) }
    }

    public func push(_ newElement: Element) {
        write { $0.insert(newElement, at: 0) }
    }

    public func pop() -> Element? {
        write { $0.popLast() }
    }

    @discardableResult
    public func remove(at index: Int) -> Element {
        write { $0.remove(at: index) }
    }

    public func removeAll(keepingCapacity keepCapacity: Bool = false) {
        write { $0.removeAll(keepingCapacity: keepCapacity) }
    }

    public func forEach(_ body: @Sendable (Element) throws -> Void) rethrows {
        try read { try $0.forEach(body) }
    }

    public func map<T: Sendable>(_ transform: @Sendable (Element) throws -> T) rethrows -> [T] {
        try read { try $0.map(transform) }
    }

    public subscript(index: Int) -> Element {
        get { read { $0[index] } }
        set { write { $0[index] = newValue } }
    }

    public subscript(safe index: Int) -> Element? {
        read { $0.indices.contains(index) ? $0[index] : nil }
    }

    /// Runs `body` as a single unit of work under the lock/queue, so compound
    /// operations (check-then-act, multi-step updates) are atomic — not just each individual call.
    public func mutate<T: Sendable>(_ body: @Sendable (inout [Element]) throws -> T) rethrows -> T {
        try write(body)
    }
}

extension ThreadSafeArray: CustomStringConvertible {
    public var description: String {
        "ThreadSafeArray(\(elements))"
    }
}

extension ThreadSafeArray: Equatable where Element: Equatable {
    public static func == (lhs: ThreadSafeArray, rhs: ThreadSafeArray) -> Bool {
        lhs.elements == rhs.elements
    }
}

extension ThreadSafeArray: Hashable where Element: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(elements)
    }
}

extension ThreadSafeArray: Codable where Element: Codable {
    public convenience init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(try container.decode([Element].self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(elements)
    }
}
