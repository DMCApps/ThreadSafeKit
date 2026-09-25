/// `subscript(index:)` is get-only: an actor subscript can't be assigned from outside the actor —
/// there's no such thing as an `async` subscript setter. `setElement(_:at:)` is the single-index
/// atomic write that fills the gap, mirroring `ThreadSafeDictionary.updateValue(_:forKey:)`'s role
/// for the dictionary shape (`await array.mutate { $0[i] = v }` also works, but touches the whole
/// array under one call rather than just this index).
///
/// `mutate` and the read-only `Collection` members come from `_ThreadSafeActorStorage`'s protocol
/// extension — see that type's doc comment for the `final`/`@inlinable`/`_storage` rationale shared
/// by all four actor types.
public final actor ThreadSafeArray<Element: Sendable>: _ThreadSafeActorStorage {
    public var _storage: [Element]

    @inlinable
    public init() {
        _storage = []
    }

    @inlinable
    public init(_ elements: some Sequence<Element>) {
        _storage = Array(elements)
    }

    @inlinable
    public var first: Element? {
        _storage.first
    }

    @inlinable
    public var last: Element? {
        _storage.last
    }

    @inlinable
    public var elements: [Element] {
        _storage
    }

    @inlinable
    public func append(_ newElement: Element) {
        _storage.append(newElement)
    }

    @inlinable
    public func append(contentsOf newElements: some Sequence<Element> & Sendable) {
        _storage.append(contentsOf: newElements)
    }

    @inlinable
    public func popLast() -> Element? {
        _storage.popLast()
    }

    @discardableResult
    @inlinable
    public func remove(at index: Int) -> Element {
        _storage.remove(at: index)
    }

    @inlinable
    public func insert(_ newElement: Element, at index: Int) {
        _storage.insert(newElement, at: index)
    }

    @inlinable
    public func insert(contentsOf newElements: some Collection<Element> & Sendable, at index: Int) {
        _storage.insert(contentsOf: newElements, at: index)
    }

    @inlinable
    public func removeAll(keepingCapacity keepCapacity: Bool = false) {
        _storage.removeAll(keepingCapacity: keepCapacity)
    }

    @inlinable
    public func removeAll(where shouldBeRemoved: @Sendable (Element) throws -> Bool) rethrows {
        try _storage.removeAll(where: shouldBeRemoved)
    }

    @discardableResult
    @inlinable
    public func removeFirst() -> Element {
        _storage.removeFirst()
    }

    @inlinable
    public func removeFirst(_ n: Int) {
        _storage.removeFirst(n)
    }

    @discardableResult
    @inlinable
    public func removeLast() -> Element {
        _storage.removeLast()
    }

    @inlinable
    public func removeLast(_ n: Int) {
        _storage.removeLast(n)
    }

    @inlinable
    public func removeSubrange(_ bounds: Range<Int>) {
        _storage.removeSubrange(bounds)
    }

    @inlinable
    public func replaceSubrange<C: Collection & Sendable>(
        _ subrange: Range<Int>,
        with newElements: C
    ) where C.Element == Element {
        _storage.replaceSubrange(subrange, with: newElements)
    }

    @inlinable
    public func reserveCapacity(_ n: Int) {
        _storage.reserveCapacity(n)
    }

    @inlinable
    public func swapAt(_ i: Int, _ j: Int) {
        _storage.swapAt(i, j)
    }

    @inlinable
    public func reverse() {
        _storage.reverse()
    }

    @inlinable
    public func shuffle() {
        _storage.shuffle()
    }

    @inlinable
    public func sort(by areInIncreasingOrder: @Sendable (Element, Element) throws -> Bool) rethrows {
        try _storage.sort(by: areInIncreasingOrder)
    }

    @inlinable
    public func firstIndex(where predicate: @Sendable (Element) throws -> Bool) rethrows -> Int? {
        try _storage.firstIndex(where: predicate)
    }

    @inlinable
    public func filter(_ isIncluded: @Sendable (Element) throws -> Bool) rethrows -> [Element] {
        try _storage.filter(isIncluded)
    }

    @inlinable
    public func prefix(_ maxLength: Int) -> [Element] {
        Array(_storage.prefix(maxLength))
    }

    @inlinable
    public func suffix(_ maxLength: Int) -> [Element] {
        Array(_storage.suffix(maxLength))
    }

    @inlinable
    public subscript(index: Int) -> Element {
        _storage[index]
    }

    /// The actor-isolated equivalent of `ThreadSafeDictionary.updateValue(_:forKey:)`: an atomic,
    /// single-index write, since `subscript(index:)` can't have a setter here (see the type's doc
    /// comment).
    @inlinable
    public func setElement(_ newValue: Element, at index: Int) {
        _storage[index] = newValue
    }

    @inlinable
    public subscript(safe index: Int) -> Element? {
        _storage.indices.contains(index) ? _storage[index] : nil
    }
}

extension ThreadSafeArray where Element: Equatable {
    @inlinable
    public func contains(_ element: Element) -> Bool {
        _storage.contains(element)
    }

    @inlinable
    public func firstIndex(of element: Element) -> Int? {
        _storage.firstIndex(of: element)
    }
}

extension ThreadSafeArray where Element: Comparable {
    @inlinable
    public func sort() {
        _storage.sort()
    }
}
