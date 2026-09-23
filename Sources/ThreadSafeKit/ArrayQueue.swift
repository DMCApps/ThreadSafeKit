import Foundation

/// DispatchQueue-backed alternative to ``ArrayActor``.
/// Uses a concurrent queue with barrier writes: reads run in parallel, writes are exclusive.
public final class ArrayQueue<Element: Sendable>: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.threadsafekit.arrayqueue", attributes: .concurrent)
    private var storage: [Element]

    public init() {
        storage = []
    }

    public init(_ elements: some Sequence<Element>) {
        storage = Array(elements)
    }

    public var count: Int {
        queue.sync { storage.count }
    }

    public var isEmpty: Bool {
        queue.sync { storage.isEmpty }
    }

    public var first: Element? {
        queue.sync { storage.first }
    }

    public var last: Element? {
        queue.sync { storage.last }
    }

    public var elements: [Element] {
        queue.sync { storage }
    }

    public func append(_ newElement: Element) {
        queue.sync(flags: .barrier) {
            storage.append(newElement)
        }
    }

    public func push(_ newElement: Element) {
        queue.sync(flags: .barrier) {
            storage.insert(newElement, at: 0)
        }
    }

    public func pop() -> Element? {
        queue.sync(flags: .barrier) {
            storage.popLast()
        }
    }

    @discardableResult
    public func remove(at index: Int) -> Element {
        queue.sync(flags: .barrier) {
            storage.remove(at: index)
        }
    }

    public func removeAll(keepingCapacity keepCapacity: Bool = false) {
        queue.sync(flags: .barrier) {
            storage.removeAll(keepingCapacity: keepCapacity)
        }
    }

    public func forEach(_ body: (Element) throws -> Void) rethrows {
        try queue.sync { try storage.forEach(body) }
    }

    public func map<T>(_ transform: (Element) throws -> T) rethrows -> [T] {
        try queue.sync { try storage.map(transform) }
    }

    public subscript(index: Int) -> Element {
        get { queue.sync { storage[index] } }
        set { queue.sync(flags: .barrier) { storage[index] = newValue } }
    }

    public subscript(safe index: Int) -> Element? {
        queue.sync { storage.indices.contains(index) ? storage[index] : nil }
    }

    /// Runs `body` as a single unit of work under the write lock, so compound
    /// operations (check-then-act, multi-step updates) are atomic — not just each individual call.
    public func mutate<T>(_ body: (inout [Element]) throws -> T) rethrows -> T {
        try queue.sync(flags: .barrier) { try body(&storage) }
    }
}

extension ArrayQueue: Equatable where Element: Equatable {
    public static func == (lhs: ArrayQueue, rhs: ArrayQueue) -> Bool {
        lhs.elements == rhs.elements
    }
}

extension ArrayQueue: Codable where Element: Codable {
    public convenience init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(try container.decode([Element].self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(elements)
    }
}
