import Foundation
import os

/// Lock/queue-backed alternative to ``ArrayActor``. Pick the backing mechanism via ``ThreadSafeMechanism``;
/// defaults to a concurrent `DispatchQueue` with barrier writes (reads run in parallel, writes are exclusive).
///
/// Also usable as a property wrapper: `wrappedValue` is a plain-array snapshot (read-only — direct
/// assignment isn't atomic across read-modify-write), and `projectedValue` is this instance itself, so
/// `$name` gives `append`/`mutate`/subscript/etc.
@propertyWrapper
public final class ThreadSafeArray<Element: Sendable>: @unchecked Sendable {
    private enum Backing {
        case lock(OSAllocatedUnfairLock<[Element]>)
        case queue(DispatchQueue)
    }

    private let backing: Backing
    // Only used by the `.queue` mechanism — the `.lock` mechanism keeps its state inside the
    // `OSAllocatedUnfairLock` instead, and only ever touches this through `read`/`write`.
    private var storage: [Element]

    public convenience init(mechanism: ThreadSafeMechanism = .dispatchQueue) {
        self.init([], mechanism: mechanism)
    }

    public convenience init(wrappedValue: [Element], mechanism: ThreadSafeMechanism = .dispatchQueue) {
        self.init(wrappedValue, mechanism: mechanism)
    }

    public init(_ elements: some Sequence<Element>, mechanism: ThreadSafeMechanism = .dispatchQueue) {
        let array = Array(elements)
        switch mechanism {
        case .lock:
            backing = .lock(OSAllocatedUnfairLock(initialState: array))
            storage = []
        case .dispatchQueue:
            backing = .queue(DispatchQueue(label: "com.threadsafekit.array", attributes: .concurrent))
            storage = array
        }
    }

    private func read<T: Sendable>(_ body: @Sendable (inout [Element]) throws -> T) rethrows -> T {
        switch backing {
        case .lock(let lock):
            return try lock.withLock(body)
        case .queue(let queue):
            return try queue.sync { try body(&storage) }
        }
    }

    private func write<T: Sendable>(_ body: @Sendable (inout [Element]) throws -> T) rethrows -> T {
        switch backing {
        case .lock(let lock):
            return try lock.withLock(body)
        case .queue(let queue):
            return try queue.sync(flags: .barrier) { try body(&storage) }
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

    public var wrappedValue: [Element] {
        get { elements }
        @available(*, unavailable, message: "Direct assignment isn't atomic across read-modify-write; use $name's append/mutate/etc. instead")
        set {}
    }

    public var projectedValue: ThreadSafeArray<Element> {
        self
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
