/// Supplies `mutate` and shared read-only members once for all four actor types; add new shared members here as `@inlinable`.
public protocol _ThreadSafeActorStorage: Actor {
    associatedtype Storage: Sendable

    /// Raw storage; public only because protocol requirements must be, and actor isolation still guards it.
    var _storage: Storage { get set }
}

extension _ThreadSafeActorStorage {
    /// Runs `body` atomically on this actor.
    @inlinable
    public func mutate<T>(_ body: (inout Storage) throws -> T) rethrows -> T {
        try body(&_storage)
    }
}

extension _ThreadSafeActorStorage where Storage: Collection, Storage.Element: Sendable {
    @inlinable
    public var count: Int {
        _storage.count
    }

    @inlinable
    public var isEmpty: Bool {
        _storage.isEmpty
    }

    @inlinable
    public func forEach(_ body: @Sendable (Storage.Element) throws -> Void) rethrows {
        try _storage.forEach(body)
    }

    @inlinable
    public func map<T: Sendable>(_ transform: @Sendable (Storage.Element) throws -> T) rethrows -> [T] {
        try _storage.map(transform)
    }

    @inlinable
    public func reduce<Result: Sendable>(
        into initial: Result,
        _ updateAccumulatingResult: @Sendable (inout Result, Storage.Element) throws -> Void
    ) rethrows -> Result {
        try _storage.reduce(into: initial, updateAccumulatingResult)
    }

    @inlinable
    public func reduce<Result: Sendable>(
        _ initialResult: Result,
        _ nextPartialResult: @Sendable (Result, Storage.Element) throws -> Result
    ) rethrows -> Result {
        try _storage.reduce(initialResult, nextPartialResult)
    }

    @inlinable
    public func first(where predicate: @Sendable (Storage.Element) throws -> Bool) rethrows -> Storage.Element? {
        try _storage.first(where: predicate)
    }

    @inlinable
    public func contains(where predicate: @Sendable (Storage.Element) throws -> Bool) rethrows -> Bool {
        try _storage.contains(where: predicate)
    }

    @inlinable
    public func count(where predicate: @Sendable (Storage.Element) throws -> Bool) rethrows -> Int {
        try _storage.count(where: predicate)
    }

    @inlinable
    public func min(by areInIncreasingOrder: @Sendable (Storage.Element, Storage.Element) throws -> Bool) rethrows -> Storage.Element? {
        try _storage.min(by: areInIncreasingOrder)
    }

    @inlinable
    public func max(by areInIncreasingOrder: @Sendable (Storage.Element, Storage.Element) throws -> Bool) rethrows -> Storage.Element? {
        try _storage.max(by: areInIncreasingOrder)
    }

    @inlinable
    public func randomElement() -> Storage.Element? {
        _storage.randomElement()
    }

    @inlinable
    public func compactMap<T: Sendable>(_ transform: @Sendable (Storage.Element) throws -> T?) rethrows -> [T] {
        try _storage.compactMap(transform)
    }

    @inlinable
    public func sorted(by areInIncreasingOrder: @Sendable (Storage.Element, Storage.Element) throws -> Bool) rethrows -> [Storage.Element] {
        try _storage.sorted(by: areInIncreasingOrder)
    }

    @inlinable
    public func allSatisfy(_ predicate: @Sendable (Storage.Element) throws -> Bool) rethrows -> Bool {
        try _storage.allSatisfy(predicate)
    }
}

extension _ThreadSafeActorStorage where Storage: Collection, Storage.Element: Sendable & Comparable {
    @inlinable
    public func sorted() -> [Storage.Element] {
        _storage.sorted()
    }

    @inlinable
    public func min() -> Storage.Element? {
        _storage.min()
    }

    @inlinable
    public func max() -> Storage.Element? {
        _storage.max()
    }
}
