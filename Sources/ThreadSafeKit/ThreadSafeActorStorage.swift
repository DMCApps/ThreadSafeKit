/// Shared storage protocol for the actor types (`ThreadSafeArray`, `ThreadSafeDictionary`,
/// `ThreadSafeSet`, `ThreadSafeAtomic`). `ThreadSafeArray`, `ThreadSafeDictionary` and `ThreadSafeSet`
/// each used to copy-paste the same ~16 read-only `Collection` members plus `mutate`; this protocol's
/// extensions supply them once instead. `Storage` stands for the *whole* wrapped type (`[Element]`,
/// `Set<Element>`, `[Key: Value]`, or the plain `Value` for `ThreadSafeAtomic`), not the element type,
/// so the members below are written against `Storage.Element` — for a dictionary that's the tuple
/// `(key: Key, value: Value)`, which is why `sorted()`/`min()`/`max()` (below, `Comparable`-constrained)
/// only reach the array and set conformances: a dictionary's tuple `Element` isn't `Comparable`.
///
/// Methods in an extension of a protocol that refines `Actor` are isolated to `Self`, so callers still
/// write `await array.count` — call sites don't change.
///
/// `final`: Swift doesn't treat actors as implicitly `final`, and calling a non-final actor's method
/// through a captured instance (e.g. inside a `@Sendable` closure passed to a `Task`) compiles to a
/// vtable call, which the compiler can't specialize/inline even when the callee is `@inlinable`. Every
/// conforming actor is `final` specifically so that call can be devirtualized and inlined into the
/// caller — don't remove `final` from any of them. Every public member here (and every public member
/// on each conforming actor) is `@inlinable` for the same reason `ThreadSafe`'s are (see the comment
/// at the top of `ThreadSafe.swift`): so a client module can specialize the call for its concrete
/// `Storage`/`Element` instead of paying for unspecialized generic dispatch. `_storage` is `public`
/// (a public protocol requirement can't be anything less) so these inlinable bodies can reach it
/// across conformances — see its own doc comment below for why it's still not meant for outside use.
/// Mark any new shared member `@inlinable` too, and add it here rather than duplicating it per actor.
public protocol _ThreadSafeActorStorage: Actor {
    associatedtype Storage: Sendable

    /// The actor's raw storage. Public only because a protocol requirement must be — not intended
    /// for outside use or outside conformance. It can't be set from outside the actor's isolation,
    /// and a cross-actor read still needs `await` and returns only an async snapshot, the same thing
    /// `elements`/`dictionary` return. Follows the `_ThreadSafeKeyedStorage` naming precedent in
    /// `ThreadSafe+Dictionary.swift`.
    var _storage: Storage { get set }
}

extension _ThreadSafeActorStorage {
    /// Runs `body` as a single unit of work isolated to this actor, so compound
    /// operations (check-then-act, multi-step updates) are atomic — not just each individual call.
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
