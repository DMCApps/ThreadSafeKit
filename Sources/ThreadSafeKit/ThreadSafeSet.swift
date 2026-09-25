/// `final`: Swift doesn't treat actors as implicitly `final`, and calling a non-final actor's method
/// through a captured instance (e.g. inside a `@Sendable` closure passed to a `Task`) compiles to a
/// vtable call, which the compiler can't specialize/inline even when the callee is `@inlinable`. This
/// type is `final` specifically so that call can be devirtualized and inlined into the caller — don't
/// remove it. Every public member is `@inlinable` for the same reason `ThreadSafe`'s are (see the
/// comment at the top of `ThreadSafe.swift`): so a client module can specialize the call for its
/// concrete `Element` instead of paying for unspecialized generic dispatch. `storage` is
/// `@usableFromInline` so those inlinable bodies can reach it — don't make it `private` again. Mark
/// any new public member `@inlinable` too.
public final actor ThreadSafeSet<Element: Hashable & Sendable> {
    @usableFromInline
    var storage: Set<Element>

    @inlinable
    public init() {
        storage = []
    }

    @inlinable
    public init(_ elements: some Sequence<Element>) {
        storage = Set(elements)
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
    public var elements: Set<Element> {
        storage
    }

    @inlinable
    public func contains(_ member: Element) -> Bool {
        storage.contains(member)
    }

    @discardableResult
    @inlinable
    public func insert(_ newMember: Element) -> (inserted: Bool, memberAfterInsert: Element) {
        storage.insert(newMember)
    }

    @discardableResult
    @inlinable
    public func remove(_ member: Element) -> Element? {
        storage.remove(member)
    }

    @discardableResult
    @inlinable
    public func update(with newMember: Element) -> Element? {
        storage.update(with: newMember)
    }

    @inlinable
    public func removeAll(keepingCapacity keepCapacity: Bool = false) {
        storage.removeAll(keepingCapacity: keepCapacity)
    }

    @inlinable
    public func popFirst() -> Element? {
        storage.popFirst()
    }

    @discardableResult
    @inlinable
    public func removeFirst() -> Element {
        storage.removeFirst()
    }

    @inlinable
    public func reserveCapacity(_ minimumCapacity: Int) {
        storage.reserveCapacity(minimumCapacity)
    }

    @inlinable
    public func union(_ other: Set<Element>) -> Set<Element> {
        storage.union(other)
    }

    @inlinable
    public func intersection(_ other: Set<Element>) -> Set<Element> {
        storage.intersection(other)
    }

    @inlinable
    public func symmetricDifference(_ other: Set<Element>) -> Set<Element> {
        storage.symmetricDifference(other)
    }

    @inlinable
    public func subtracting(_ other: Set<Element>) -> Set<Element> {
        storage.subtracting(other)
    }

    @inlinable
    public func formUnion(_ other: Set<Element>) {
        storage.formUnion(other)
    }

    @inlinable
    public func formIntersection(_ other: Set<Element>) {
        storage.formIntersection(other)
    }

    @inlinable
    public func subtract(_ other: Set<Element>) {
        storage.subtract(other)
    }

    @inlinable
    public func formSymmetricDifference(_ other: Set<Element>) {
        storage.formSymmetricDifference(other)
    }

    @inlinable
    public func isSubset(of other: Set<Element>) -> Bool {
        storage.isSubset(of: other)
    }

    @inlinable
    public func isSuperset(of other: Set<Element>) -> Bool {
        storage.isSuperset(of: other)
    }

    @inlinable
    public func isDisjoint(with other: Set<Element>) -> Bool {
        storage.isDisjoint(with: other)
    }

    @inlinable
    public func isStrictSubset(of other: Set<Element>) -> Bool {
        storage.isStrictSubset(of: other)
    }

    @inlinable
    public func isStrictSuperset(of other: Set<Element>) -> Bool {
        storage.isStrictSuperset(of: other)
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
    public func filter(_ isIncluded: @Sendable (Element) throws -> Bool) rethrows -> Set<Element> {
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

    /// Runs `body` as a single unit of work isolated to this actor, so compound
    /// operations (check-then-act, multi-step updates) are atomic — not just each individual call.
    @inlinable
    public func mutate<T>(_ body: (inout Set<Element>) throws -> T) rethrows -> T {
        try body(&storage)
    }
}

extension ThreadSafeSet where Element: Comparable {
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
