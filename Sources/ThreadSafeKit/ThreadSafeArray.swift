/// Deliberately not `Codable`: `Encodable.encode(to:)` is synchronous, but reading
/// isolated actor state requires `await`, so no `encode(to:)` can call ``elements``.
/// `Decodable` alone only compiles as a `@preconcurrency` conformance (a non-`Sendable`
/// `Decoder` can't otherwise be passed into the actor's initializer), and a decode-only type
/// would be asymmetric and surprising, so it's left out too.
/// To (de)serialize, snapshot/restore manually at the call site: encode `await elements`,
/// decode into `ThreadSafeArray(_:)`.
///
/// `subscript(index:)` is get-only: an actor subscript can't be assigned from outside the actor —
/// there's no such thing as an `async` subscript setter. `setElement(_:at:)` is the single-index
/// atomic write that fills the gap, mirroring `ThreadSafeDictionary.updateValue(_:forKey:)`'s role
/// for the dictionary shape (`await array.mutate { $0[i] = v }` also works, but touches the whole
/// array under one call rather than just this index).
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

    public func append(contentsOf newElements: some Sequence<Element> & Sendable) {
        storage.append(contentsOf: newElements)
    }

    public func popLast() -> Element? {
        storage.popLast()
    }

    @discardableResult
    public func remove(at index: Int) -> Element {
        storage.remove(at: index)
    }

    public func insert(_ newElement: Element, at index: Int) {
        storage.insert(newElement, at: index)
    }

    public func insert(contentsOf newElements: some Collection<Element> & Sendable, at index: Int) {
        storage.insert(contentsOf: newElements, at: index)
    }

    public func removeAll(keepingCapacity keepCapacity: Bool = false) {
        storage.removeAll(keepingCapacity: keepCapacity)
    }

    public func removeAll(where shouldBeRemoved: @Sendable (Element) throws -> Bool) rethrows {
        try storage.removeAll(where: shouldBeRemoved)
    }

    @discardableResult
    public func removeFirst() -> Element {
        storage.removeFirst()
    }

    public func removeFirst(_ n: Int) {
        storage.removeFirst(n)
    }

    @discardableResult
    public func removeLast() -> Element {
        storage.removeLast()
    }

    public func removeLast(_ n: Int) {
        storage.removeLast(n)
    }

    public func removeSubrange(_ bounds: Range<Int>) {
        storage.removeSubrange(bounds)
    }

    public func replaceSubrange<C: Collection & Sendable>(
        _ subrange: Range<Int>,
        with newElements: C
    ) where C.Element == Element {
        storage.replaceSubrange(subrange, with: newElements)
    }

    public func reserveCapacity(_ n: Int) {
        storage.reserveCapacity(n)
    }

    public func swapAt(_ i: Int, _ j: Int) {
        storage.swapAt(i, j)
    }

    public func reverse() {
        storage.reverse()
    }

    public func shuffle() {
        storage.shuffle()
    }

    public func sort(by areInIncreasingOrder: @Sendable (Element, Element) throws -> Bool) rethrows {
        try storage.sort(by: areInIncreasingOrder)
    }

    public func firstIndex(where predicate: @Sendable (Element) throws -> Bool) rethrows -> Int? {
        try storage.firstIndex(where: predicate)
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

    public func filter(_ isIncluded: @Sendable (Element) throws -> Bool) rethrows -> [Element] {
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

    public func prefix(_ maxLength: Int) -> [Element] {
        Array(storage.prefix(maxLength))
    }

    public func suffix(_ maxLength: Int) -> [Element] {
        Array(storage.suffix(maxLength))
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

    public subscript(index: Int) -> Element {
        storage[index]
    }

    /// The actor-isolated equivalent of `ThreadSafeDictionary.updateValue(_:forKey:)`: an atomic,
    /// single-index write, since `subscript(index:)` can't have a setter here (see the type's doc
    /// comment).
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

extension ThreadSafeArray where Element: Equatable {
    public func contains(_ element: Element) -> Bool {
        storage.contains(element)
    }

    public func firstIndex(of element: Element) -> Int? {
        storage.firstIndex(of: element)
    }
}

extension ThreadSafeArray where Element: Comparable {
    public func sort() {
        storage.sort()
    }

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
