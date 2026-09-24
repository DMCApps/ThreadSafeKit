/// Deliberately not `Codable`: `Encodable.encode(to:)` is synchronous, but reading
/// isolated actor state requires `await`, so no `encode(to:)` can call ``elements``.
/// `init(from:)` could be implemented (actor initializers aren't async), but doing so
/// alone would give asymmetric, surprising conformance, so it's left out too.
/// To (de)serialize, snapshot/restore manually at the call site: encode `await elements`,
/// decode into `ThreadSafeSet(_:)`.
public actor ThreadSafeSet<Element: Hashable & Sendable> {
    private var storage: Set<Element>

    public init() {
        storage = []
    }

    public init(_ elements: some Sequence<Element>) {
        storage = Set(elements)
    }

    public var count: Int {
        storage.count
    }

    public var isEmpty: Bool {
        storage.isEmpty
    }

    public var elements: Set<Element> {
        storage
    }

    public func contains(_ member: Element) -> Bool {
        storage.contains(member)
    }

    @discardableResult
    public func insert(_ newMember: Element) -> (inserted: Bool, memberAfterInsert: Element) {
        storage.insert(newMember)
    }

    @discardableResult
    public func remove(_ member: Element) -> Element? {
        storage.remove(member)
    }

    @discardableResult
    public func update(with newMember: Element) -> Element? {
        storage.update(with: newMember)
    }

    public func removeAll(keepingCapacity keepCapacity: Bool = false) {
        storage.removeAll(keepingCapacity: keepCapacity)
    }

    public func union(_ other: Set<Element>) -> Set<Element> {
        storage.union(other)
    }

    public func intersection(_ other: Set<Element>) -> Set<Element> {
        storage.intersection(other)
    }

    public func symmetricDifference(_ other: Set<Element>) -> Set<Element> {
        storage.symmetricDifference(other)
    }

    public func formUnion(_ other: Set<Element>) {
        storage.formUnion(other)
    }

    public func formIntersection(_ other: Set<Element>) {
        storage.formIntersection(other)
    }

    public func subtract(_ other: Set<Element>) {
        storage.subtract(other)
    }

    public func formSymmetricDifference(_ other: Set<Element>) {
        storage.formSymmetricDifference(other)
    }

    public func isSubset(of other: Set<Element>) -> Bool {
        storage.isSubset(of: other)
    }

    public func isSuperset(of other: Set<Element>) -> Bool {
        storage.isSuperset(of: other)
    }

    public func isDisjoint(with other: Set<Element>) -> Bool {
        storage.isDisjoint(with: other)
    }

    public func isStrictSubset(of other: Set<Element>) -> Bool {
        storage.isStrictSubset(of: other)
    }

    public func isStrictSuperset(of other: Set<Element>) -> Bool {
        storage.isStrictSuperset(of: other)
    }

    public func forEach(_ body: @Sendable (Element) throws -> Void) rethrows {
        try storage.forEach(body)
    }

    public func map<T: Sendable>(_ transform: @Sendable (Element) throws -> T) rethrows -> [T] {
        try storage.map(transform)
    }

    /// Runs `body` as a single unit of work isolated to this actor, so compound
    /// operations (check-then-act, multi-step updates) are atomic — not just each individual call.
    public func mutate<T>(_ body: (inout Set<Element>) throws -> T) rethrows -> T {
        try body(&storage)
    }
}
