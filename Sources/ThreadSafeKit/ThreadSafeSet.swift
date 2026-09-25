/// `mutate` and the read-only `Collection` members come from `_ThreadSafeActorStorage`'s protocol
/// extension — see that type's doc comment for the `final`/`@inlinable`/`_storage` rationale shared
/// by all four actor types.
public final actor ThreadSafeSet<Element: Hashable & Sendable>: _ThreadSafeActorStorage {
    public var _storage: Set<Element>

    @inlinable
    public init() {
        _storage = []
    }

    @inlinable
    public init(_ elements: some Sequence<Element>) {
        _storage = Set(elements)
    }

    @inlinable
    public var elements: Set<Element> {
        _storage
    }

    @inlinable
    public func contains(_ member: Element) -> Bool {
        _storage.contains(member)
    }

    @discardableResult
    @inlinable
    public func insert(_ newMember: Element) -> (inserted: Bool, memberAfterInsert: Element) {
        _storage.insert(newMember)
    }

    @discardableResult
    @inlinable
    public func remove(_ member: Element) -> Element? {
        _storage.remove(member)
    }

    @discardableResult
    @inlinable
    public func update(with newMember: Element) -> Element? {
        _storage.update(with: newMember)
    }

    @inlinable
    public func removeAll(keepingCapacity keepCapacity: Bool = false) {
        _storage.removeAll(keepingCapacity: keepCapacity)
    }

    @inlinable
    public func popFirst() -> Element? {
        _storage.popFirst()
    }

    @discardableResult
    @inlinable
    public func removeFirst() -> Element {
        _storage.removeFirst()
    }

    @inlinable
    public func reserveCapacity(_ minimumCapacity: Int) {
        _storage.reserveCapacity(minimumCapacity)
    }

    @inlinable
    public func union(_ other: Set<Element>) -> Set<Element> {
        _storage.union(other)
    }

    @inlinable
    public func intersection(_ other: Set<Element>) -> Set<Element> {
        _storage.intersection(other)
    }

    @inlinable
    public func symmetricDifference(_ other: Set<Element>) -> Set<Element> {
        _storage.symmetricDifference(other)
    }

    @inlinable
    public func subtracting(_ other: Set<Element>) -> Set<Element> {
        _storage.subtracting(other)
    }

    @inlinable
    public func formUnion(_ other: Set<Element>) {
        _storage.formUnion(other)
    }

    @inlinable
    public func formIntersection(_ other: Set<Element>) {
        _storage.formIntersection(other)
    }

    @inlinable
    public func subtract(_ other: Set<Element>) {
        _storage.subtract(other)
    }

    @inlinable
    public func formSymmetricDifference(_ other: Set<Element>) {
        _storage.formSymmetricDifference(other)
    }

    @inlinable
    public func isSubset(of other: Set<Element>) -> Bool {
        _storage.isSubset(of: other)
    }

    @inlinable
    public func isSuperset(of other: Set<Element>) -> Bool {
        _storage.isSuperset(of: other)
    }

    @inlinable
    public func isDisjoint(with other: Set<Element>) -> Bool {
        _storage.isDisjoint(with: other)
    }

    @inlinable
    public func isStrictSubset(of other: Set<Element>) -> Bool {
        _storage.isStrictSubset(of: other)
    }

    @inlinable
    public func isStrictSuperset(of other: Set<Element>) -> Bool {
        _storage.isStrictSuperset(of: other)
    }

    @inlinable
    public func filter(_ isIncluded: @Sendable (Element) throws -> Bool) rethrows -> Set<Element> {
        try _storage.filter(isIncluded)
    }
}
