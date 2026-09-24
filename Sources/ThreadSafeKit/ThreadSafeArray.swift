/// Deliberately not `Codable`: `Encodable.encode(to:)` is synchronous, but reading
/// isolated actor state requires `await`, so no `encode(to:)` can call ``elements``.
/// `init(from:)` could be implemented (actor initializers aren't async), but doing so
/// alone would give asymmetric, surprising conformance, so it's left out too.
/// To (de)serialize, snapshot/restore manually at the call site: encode `await elements`,
/// decode into `ThreadSafeArray(_:)`.
public actor ThreadSafeArray<Element: Sendable> {
    private var storage: [Element]

    public init() {
        storage = []
    }

    public init(_ elements: some Sequence<Element>) {
        storage = Array(elements)
    }

    public var count: Int {
        storage.count
    }

    public var isEmpty: Bool {
        storage.isEmpty
    }

    public var first: Element? {
        storage.first
    }

    public var last: Element? {
        storage.last
    }

    public var elements: [Element] {
        storage
    }

    public func append(_ newElement: Element) {
        storage.append(newElement)
    }

    public func push(_ newElement: Element) {
        storage.insert(newElement, at: 0)
    }

    public func pop() -> Element? {
        storage.popLast()
    }

    @discardableResult
    public func remove(at index: Int) -> Element {
        storage.remove(at: index)
    }

    public func removeAll(keepingCapacity keepCapacity: Bool = false) {
        storage.removeAll(keepingCapacity: keepCapacity)
    }

    public func forEach(_ body: @Sendable (Element) throws -> Void) rethrows {
        try storage.forEach(body)
    }

    public func map<T: Sendable>(_ transform: @Sendable (Element) throws -> T) rethrows -> [T] {
        try storage.map(transform)
    }

    public subscript(index: Int) -> Element {
        storage[index]
    }

    public func setElement(_ newValue: Element, at index: Int) {
        storage[index] = newValue
    }

    public subscript(safe index: Int) -> Element? {
        storage.indices.contains(index) ? storage[index] : nil
    }

    /// Runs `body` as a single unit of work isolated to this actor, so compound
    /// operations (check-then-act, multi-step updates) are atomic — not just each individual call.
    public func mutate<T>(_ body: (inout [Element]) throws -> T) rethrows -> T {
        try body(&storage)
    }
}
