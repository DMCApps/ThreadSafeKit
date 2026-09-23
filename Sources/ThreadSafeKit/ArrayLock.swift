import os

/// Lock-backed alternative to ``ArrayActor``, using `OSAllocatedUnfairLock` instead of an actor.
public final class ArrayLock<Element: Sendable>: Sendable {
    private let lock: OSAllocatedUnfairLock<[Element]>

    public init() {
        lock = OSAllocatedUnfairLock(initialState: [])
    }

    public init(_ elements: some Sequence<Element>) {
        lock = OSAllocatedUnfairLock(initialState: Array(elements))
    }

    public var count: Int {
        lock.withLock { $0.count }
    }

    public var isEmpty: Bool {
        lock.withLock { $0.isEmpty }
    }

    public var first: Element? {
        lock.withLock { $0.first }
    }

    public var last: Element? {
        lock.withLock { $0.last }
    }

    public var elements: [Element] {
        lock.withLock { $0 }
    }

    public func append(_ newElement: Element) {
        lock.withLock { $0.append(newElement) }
    }

    public func push(_ newElement: Element) {
        lock.withLock { $0.insert(newElement, at: 0) }
    }

    public func pop() -> Element? {
        lock.withLock { $0.popLast() }
    }

    @discardableResult
    public func remove(at index: Int) -> Element {
        lock.withLock { $0.remove(at: index) }
    }

    public func removeAll(keepingCapacity keepCapacity: Bool = false) {
        lock.withLock { $0.removeAll(keepingCapacity: keepCapacity) }
    }

    public func forEach(_ body: @Sendable (Element) throws -> Void) rethrows {
        try lock.withLock { try $0.forEach(body) }
    }

    public func map<T: Sendable>(_ transform: @Sendable (Element) throws -> T) rethrows -> [T] {
        try lock.withLock { try $0.map(transform) }
    }

    public subscript(index: Int) -> Element {
        get { lock.withLock { $0[index] } }
        set { lock.withLock { $0[index] = newValue } }
    }

    public subscript(safe index: Int) -> Element? {
        lock.withLock { $0.indices.contains(index) ? $0[index] : nil }
    }

    /// Runs `body` as a single unit of work under the lock, so compound
    /// operations (check-then-act, multi-step updates) are atomic — not just each individual call.
    public func mutate<T: Sendable>(_ body: @Sendable (inout [Element]) throws -> T) rethrows -> T {
        try lock.withLock(body)
    }
}

extension ArrayLock: Equatable where Element: Equatable {
    public static func == (lhs: ArrayLock, rhs: ArrayLock) -> Bool {
        lhs.elements == rhs.elements
    }
}

extension ArrayLock: Hashable where Element: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(elements)
    }
}

extension ArrayLock: Codable where Element: Codable {
    public convenience init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(try container.decode([Element].self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(elements)
    }
}
