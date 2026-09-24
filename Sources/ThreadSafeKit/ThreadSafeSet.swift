/// Deliberately not `Codable`: `Encodable.encode(to:)` is synchronous, but reading
/// isolated actor state requires `await`, so no `encode(to:)` can call ``elements``.
/// `Decodable` alone only compiles as a `@preconcurrency` conformance (a non-`Sendable`
/// `Decoder` can't otherwise be passed into the actor's initializer), and a decode-only type
/// would be asymmetric and surprising, so it's left out too.
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

    public func popFirst() -> Element? {
        storage.popFirst()
    }

    @discardableResult
    public func removeFirst() -> Element {
        storage.removeFirst()
    }

    public func reserveCapacity(_ minimumCapacity: Int) {
        storage.reserveCapacity(minimumCapacity)
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

    public func subtracting(_ other: Set<Element>) -> Set<Element> {
        storage.subtracting(other)
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

    public func first(where predicate: @Sendable (Element) throws -> Bool) rethrows -> Element? {
        try storage.first(where: predicate)
    }

    public func contains(where predicate: @Sendable (Element) throws -> Bool) rethrows -> Bool {
        try storage.contains(where: predicate)
    }

    public func count(where predicate: @Sendable (Element) throws -> Bool) rethrows -> Int {
        try storage.count(where: predicate)
    }

    public func min(by areInIncreasingOrder: @Sendable (Element, Element) throws -> Bool) rethrows -> Element? {
        try storage.min(by: areInIncreasingOrder)
    }

    public func max(by areInIncreasingOrder: @Sendable (Element, Element) throws -> Bool) rethrows -> Element? {
        try storage.max(by: areInIncreasingOrder)
    }

    public func randomElement() -> Element? {
        storage.randomElement()
    }

    public func filter(_ isIncluded: @Sendable (Element) throws -> Bool) rethrows -> Set<Element> {
        try storage.filter(isIncluded)
    }

    public func compactMap<T: Sendable>(_ transform: @Sendable (Element) throws -> T?) rethrows -> [T] {
        try storage.compactMap(transform)
    }

    public func sorted(by areInIncreasingOrder: @Sendable (Element, Element) throws -> Bool) rethrows -> [Element] {
        try storage.sorted(by: areInIncreasingOrder)
    }

    public func allSatisfy(_ predicate: @Sendable (Element) throws -> Bool) rethrows -> Bool {
        try storage.allSatisfy(predicate)
    }

    public func forEach(_ body: @Sendable (Element) throws -> Void) rethrows {
        try storage.forEach(body)
    }

    public func map<T: Sendable>(_ transform: @Sendable (Element) throws -> T) rethrows -> [T] {
        try storage.map(transform)
    }

    public func reduce<Result: Sendable>(
        into initial: Result,
        _ updateAccumulatingResult: @Sendable (inout Result, Element) throws -> Void
    ) rethrows -> Result {
        try storage.reduce(into: initial, updateAccumulatingResult)
    }

    public func reduce<Result: Sendable>(
        _ initialResult: Result,
        _ nextPartialResult: @Sendable (Result, Element) throws -> Result
    ) rethrows -> Result {
        try storage.reduce(initialResult, nextPartialResult)
    }

    /// Runs `body` as a single unit of work isolated to this actor, so compound
    /// operations (check-then-act, multi-step updates) are atomic — not just each individual call.
    public func mutate<T>(_ body: (inout Set<Element>) throws -> T) rethrows -> T {
        try body(&storage)
    }
}

extension ThreadSafeSet where Element: Comparable {
    public func sorted() -> [Element] {
        storage.sorted()
    }

    public func min() -> Element? {
        storage.min()
    }

    public func max() -> Element? {
        storage.max()
    }
}
