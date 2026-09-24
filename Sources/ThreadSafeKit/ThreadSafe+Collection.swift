extension ThreadSafe where Value: Collection, Value.Element: Sendable {
    @inlinable
    public var count: Int { read { $0.count } }
    @inlinable
    public var isEmpty: Bool { read { $0.isEmpty } }

    @inlinable
    public func forEach(_ body: @Sendable (Value.Element) throws -> Void) rethrows {
        try read { try $0.forEach(body) }
    }

    @inlinable
    public func map<T: Sendable>(_ transform: @Sendable (Value.Element) throws -> T) rethrows -> [T] {
        try read { try $0.map(transform) }
    }

    @inlinable
    public func reduce<Result: Sendable>(
        into initial: Result,
        _ updateAccumulatingResult: @Sendable (inout Result, Value.Element) throws -> Void
    ) rethrows -> Result {
        try read { try $0.reduce(into: initial, updateAccumulatingResult) }
    }

    @inlinable
    public func reduce<Result: Sendable>(
        _ initialResult: Result,
        _ nextPartialResult: @Sendable (Result, Value.Element) throws -> Result
    ) rethrows -> Result {
        try read { try $0.reduce(initialResult, nextPartialResult) }
    }

    @inlinable
    public func first(where predicate: @Sendable (Value.Element) throws -> Bool) rethrows -> Value.Element? {
        try read { try $0.first(where: predicate) }
    }

    @inlinable
    public func contains(where predicate: @Sendable (Value.Element) throws -> Bool) rethrows -> Bool {
        try read { try $0.contains(where: predicate) }
    }

    @inlinable
    public func count(where predicate: @Sendable (Value.Element) throws -> Bool) rethrows -> Int {
        try read { try $0.count(where: predicate) }
    }

    @inlinable
    public func min(by areInIncreasingOrder: @Sendable (Value.Element, Value.Element) throws -> Bool) rethrows -> Value.Element? {
        try read { try $0.min(by: areInIncreasingOrder) }
    }

    @inlinable
    public func max(by areInIncreasingOrder: @Sendable (Value.Element, Value.Element) throws -> Bool) rethrows -> Value.Element? {
        try read { try $0.max(by: areInIncreasingOrder) }
    }

    @inlinable
    public func randomElement() -> Value.Element? {
        read { $0.randomElement() }
    }

    @inlinable
    public func compactMap<T: Sendable>(_ transform: @Sendable (Value.Element) throws -> T?) rethrows -> [T] {
        try read { try $0.compactMap(transform) }
    }

    @inlinable
    public func sorted(by areInIncreasingOrder: @Sendable (Value.Element, Value.Element) throws -> Bool) rethrows -> [Value.Element] {
        try read { try $0.sorted(by: areInIncreasingOrder) }
    }

    @inlinable
    public func allSatisfy(_ predicate: @Sendable (Value.Element) throws -> Bool) rethrows -> Bool {
        try read { try $0.allSatisfy(predicate) }
    }
}

extension ThreadSafe where Value: Collection, Value.Element: Sendable & Comparable {
    @inlinable
    public func sorted() -> [Value.Element] {
        read { $0.sorted() }
    }

    @inlinable
    public func min() -> Value.Element? {
        read { $0.min() }
    }

    @inlinable
    public func max() -> Value.Element? {
        read { $0.max() }
    }
}

extension ThreadSafe where Value: Collection, Value.Element: Sendable, Value.Index: Sendable {
    @inlinable
    public subscript(safe index: Value.Index) -> Value.Element? {
        read { $0.indices.contains(index) ? $0[index] : nil }
    }
}

// `first`/`last` live here (BidirectionalCollection), not on the general Collection extension above,
// so a dictionary shape — Collection but not BidirectionalCollection — doesn't advertise a
// nondeterministic `first`.
extension ThreadSafe where Value: BidirectionalCollection, Value.Element: Sendable {
    @inlinable
    public var first: Value.Element? { read { $0.first } }
    @inlinable
    public var last: Value.Element? { read { $0.last } }
}
