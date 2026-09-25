/// `subscript(index:)` is get-only: an actor subscript can't be assigned from outside the actor —
/// there's no such thing as an `async` subscript setter. `setElement(_:at:)` is the single-index
/// atomic write that fills the gap, mirroring `ThreadSafeDictionary.updateValue(_:forKey:)`'s role
/// for the dictionary shape (`await array.mutate { $0[i] = v }` also works, but touches the whole
/// array under one call rather than just this index).
///
/// `final`: Swift doesn't treat actors as implicitly `final`, and calling a non-final actor's method
/// through a captured instance (e.g. inside a `@Sendable` closure passed to a `Task`) compiles to a
/// vtable call, which the compiler can't specialize/inline even when the callee is `@inlinable`. This
/// type is `final` specifically so that call can be devirtualized and inlined into the caller — don't
/// remove it. Every public member is `@inlinable` for the same reason `ThreadSafe`'s are (see the
/// comment at the top of `ThreadSafe.swift`): so a client module can specialize the call for its
/// concrete `Element` instead of paying for unspecialized generic dispatch. `storage` is
/// `@usableFromInline` so those inlinable bodies can reach it — don't make it `private` again. Mark
/// any new public member `@inlinable` too.
public final actor ThreadSafeArray<Element: Sendable> {
    @usableFromInline
    var storage: [Element]

    @inlinable
    public init() {
        storage = []
    }

    @inlinable
    public init(_ elements: some Sequence<Element>) {
        storage = Array(elements)
    }

    @inlinable
    public var count: Int {
        storage.count
    }

    @inlinable
    public var isEmpty: Bool {
        storage.isEmpty
    }

    @inlinable
    public var first: Element? {
        storage.first
    }

    @inlinable
    public var last: Element? {
        storage.last
    }

    @inlinable
    public var elements: [Element] {
        storage
    }

    @inlinable
    public func append(_ newElement: Element) {
        storage.append(newElement)
    }

    @inlinable
    public func append(contentsOf newElements: some Sequence<Element> & Sendable) {
        storage.append(contentsOf: newElements)
    }

    @inlinable
    public func popLast() -> Element? {
        storage.popLast()
    }

    @discardableResult
    @inlinable
    public func remove(at index: Int) -> Element {
        storage.remove(at: index)
    }

    @inlinable
    public func insert(_ newElement: Element, at index: Int) {
        storage.insert(newElement, at: index)
    }

    @inlinable
    public func insert(contentsOf newElements: some Collection<Element> & Sendable, at index: Int) {
        storage.insert(contentsOf: newElements, at: index)
    }

    @inlinable
    public func removeAll(keepingCapacity keepCapacity: Bool = false) {
        storage.removeAll(keepingCapacity: keepCapacity)
    }

    @inlinable
    public func removeAll(where shouldBeRemoved: @Sendable (Element) throws -> Bool) rethrows {
        try storage.removeAll(where: shouldBeRemoved)
    }

    @discardableResult
    @inlinable
    public func removeFirst() -> Element {
        storage.removeFirst()
    }

    @inlinable
    public func removeFirst(_ n: Int) {
        storage.removeFirst(n)
    }

    @discardableResult
    @inlinable
    public func removeLast() -> Element {
        storage.removeLast()
    }

    @inlinable
    public func removeLast(_ n: Int) {
        storage.removeLast(n)
    }

    @inlinable
    public func removeSubrange(_ bounds: Range<Int>) {
        storage.removeSubrange(bounds)
    }

    @inlinable
    public func replaceSubrange<C: Collection & Sendable>(
        _ subrange: Range<Int>,
        with newElements: C
    ) where C.Element == Element {
        storage.replaceSubrange(subrange, with: newElements)
    }

    @inlinable
    public func reserveCapacity(_ n: Int) {
        storage.reserveCapacity(n)
    }

    @inlinable
    public func swapAt(_ i: Int, _ j: Int) {
        storage.swapAt(i, j)
    }

    @inlinable
    public func reverse() {
        storage.reverse()
    }

    @inlinable
    public func shuffle() {
        storage.shuffle()
    }

    @inlinable
    public func sort(by areInIncreasingOrder: @Sendable (Element, Element) throws -> Bool) rethrows {
        try storage.sort(by: areInIncreasingOrder)
    }

    @inlinable
    public func firstIndex(where predicate: @Sendable (Element) throws -> Bool) rethrows -> Int? {
        try storage.firstIndex(where: predicate)
    }

    @inlinable
    public func first(where predicate: @Sendable (Element) throws -> Bool) rethrows -> Element? {
        try storage.first(where: predicate)
    }

    @inlinable
    public func contains(where predicate: @Sendable (Element) throws -> Bool) rethrows -> Bool {
        try storage.contains(where: predicate)
    }

    @inlinable
    public func count(where predicate: @Sendable (Element) throws -> Bool) rethrows -> Int {
        try storage.count(where: predicate)
    }

    @inlinable
    public func min(by areInIncreasingOrder: @Sendable (Element, Element) throws -> Bool) rethrows -> Element? {
        try storage.min(by: areInIncreasingOrder)
    }

    @inlinable
    public func max(by areInIncreasingOrder: @Sendable (Element, Element) throws -> Bool) rethrows -> Element? {
        try storage.max(by: areInIncreasingOrder)
    }

    @inlinable
    public func randomElement() -> Element? {
        storage.randomElement()
    }

    @inlinable
    public func filter(_ isIncluded: @Sendable (Element) throws -> Bool) rethrows -> [Element] {
        try storage.filter(isIncluded)
    }

    @inlinable
    public func compactMap<T: Sendable>(_ transform: @Sendable (Element) throws -> T?) rethrows -> [T] {
        try storage.compactMap(transform)
    }

    @inlinable
    public func sorted(by areInIncreasingOrder: @Sendable (Element, Element) throws -> Bool) rethrows -> [Element] {
        try storage.sorted(by: areInIncreasingOrder)
    }

    @inlinable
    public func allSatisfy(_ predicate: @Sendable (Element) throws -> Bool) rethrows -> Bool {
        try storage.allSatisfy(predicate)
    }

    @inlinable
    public func prefix(_ maxLength: Int) -> [Element] {
        Array(storage.prefix(maxLength))
    }

    @inlinable
    public func suffix(_ maxLength: Int) -> [Element] {
        Array(storage.suffix(maxLength))
    }

    @inlinable
    public func forEach(_ body: @Sendable (Element) throws -> Void) rethrows {
        try storage.forEach(body)
    }

    @inlinable
    public func map<T: Sendable>(_ transform: @Sendable (Element) throws -> T) rethrows -> [T] {
        try storage.map(transform)
    }

    @inlinable
    public func reduce<Result: Sendable>(
        into initial: Result,
        _ updateAccumulatingResult: @Sendable (inout Result, Element) throws -> Void
    ) rethrows -> Result {
        try storage.reduce(into: initial, updateAccumulatingResult)
    }

    @inlinable
    public func reduce<Result: Sendable>(
        _ initialResult: Result,
        _ nextPartialResult: @Sendable (Result, Element) throws -> Result
    ) rethrows -> Result {
        try storage.reduce(initialResult, nextPartialResult)
    }

    @inlinable
    public subscript(index: Int) -> Element {
        storage[index]
    }

    /// The actor-isolated equivalent of `ThreadSafeDictionary.updateValue(_:forKey:)`: an atomic,
    /// single-index write, since `subscript(index:)` can't have a setter here (see the type's doc
    /// comment).
    @inlinable
    public func setElement(_ newValue: Element, at index: Int) {
        storage[index] = newValue
    }

    @inlinable
    public subscript(safe index: Int) -> Element? {
        storage.indices.contains(index) ? storage[index] : nil
    }

    /// Runs `body` as a single unit of work isolated to this actor, so compound
    /// operations (check-then-act, multi-step updates) are atomic — not just each individual call.
    @inlinable
    public func mutate<T>(_ body: (inout [Element]) throws -> T) rethrows -> T {
        try body(&storage)
    }
}

extension ThreadSafeArray where Element: Equatable {
    @inlinable
    public func contains(_ element: Element) -> Bool {
        storage.contains(element)
    }

    @inlinable
    public func firstIndex(of element: Element) -> Int? {
        storage.firstIndex(of: element)
    }
}

extension ThreadSafeArray where Element: Comparable {
    @inlinable
    public func sort() {
        storage.sort()
    }

    @inlinable
    public func sorted() -> [Element] {
        storage.sorted()
    }

    @inlinable
    public func min() -> Element? {
        storage.min()
    }

    @inlinable
    public func max() -> Element? {
        storage.max()
    }
}
