/// `final`: Swift doesn't treat actors as implicitly `final`, and calling a non-final actor's method
/// through a captured instance (e.g. inside a `@Sendable` closure passed to a `Task`) compiles to a
/// vtable call, which the compiler can't specialize/inline even when the callee is `@inlinable`. This
/// type is `final` specifically so that call can be devirtualized and inlined into the caller — don't
/// remove it. Every public member is `@inlinable` for the same reason `ThreadSafe`'s are (see the
/// comment at the top of `ThreadSafe.swift`): so a client module can specialize the call for its
/// concrete `Key`/`Value` instead of paying for unspecialized generic dispatch. `storage` is
/// `@usableFromInline` so those inlinable bodies can reach it — don't make it `private` again. Mark
/// any new public member `@inlinable` too.
public final actor ThreadSafeDictionary<Key: Hashable & Sendable, Value: Sendable> {
    @usableFromInline
    var storage: [Key: Value]

    @inlinable
    public init(_ dictionary: [Key: Value] = [:]) {
        storage = dictionary
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
    public var dictionary: [Key: Value] {
        storage
    }

    @inlinable
    public var keys: Dictionary<Key, Value>.Keys {
        storage.keys
    }

    @inlinable
    public var values: Dictionary<Key, Value>.Values {
        storage.values
    }

    @discardableResult
    @inlinable
    public func removeValue(forKey key: Key) -> Value? {
        storage.removeValue(forKey: key)
    }

    @discardableResult
    @inlinable
    public func updateValue(_ value: Value, forKey key: Key) -> Value? {
        storage.updateValue(value, forKey: key)
    }

    @inlinable
    public func removeAll(keepingCapacity keepCapacity: Bool = false) {
        storage.removeAll(keepingCapacity: keepCapacity)
    }

    @inlinable
    public func popFirst() -> (key: Key, value: Value)? {
        storage.popFirst()
    }

    @inlinable
    public func reserveCapacity(_ minimumCapacity: Int) {
        storage.reserveCapacity(minimumCapacity)
    }

    @inlinable
    public func merge(_ other: [Key: Value], uniquingKeysWith combine: @Sendable (Value, Value) throws -> Value) rethrows {
        try storage.merge(other, uniquingKeysWith: combine)
    }

    /// The sequence-of-pairs overload, alongside the whole-dictionary one above.
    @inlinable
    public func merge(
        _ other: some Sequence<(Key, Value)> & Sendable,
        uniquingKeysWith combine: @Sendable (Value, Value) throws -> Value
    ) rethrows {
        try storage.merge(other, uniquingKeysWith: combine)
    }

    @inlinable
    public func mapValues<T: Sendable>(_ transform: @Sendable (Value) throws -> T) rethrows -> [Key: T] {
        try storage.mapValues(transform)
    }

    @inlinable
    public func compactMapValues<T: Sendable>(_ transform: @Sendable (Value) throws -> T?) rethrows -> [Key: T] {
        try storage.compactMapValues(transform)
    }

    @inlinable
    public func filter(_ isIncluded: @Sendable ((key: Key, value: Value)) throws -> Bool) rethrows -> [Key: Value] {
        try storage.filter(isIncluded)
    }

    @inlinable
    public func contains(where predicate: @Sendable ((key: Key, value: Value)) throws -> Bool) rethrows -> Bool {
        try storage.contains(where: predicate)
    }

    @inlinable
    public func first(where predicate: @Sendable ((key: Key, value: Value)) throws -> Bool) rethrows -> (key: Key, value: Value)? {
        try storage.first(where: predicate)
    }

    @inlinable
    public func count(where predicate: @Sendable ((key: Key, value: Value)) throws -> Bool) rethrows -> Int {
        try storage.count(where: predicate)
    }

    @inlinable
    public func min(
        by areInIncreasingOrder: @Sendable ((key: Key, value: Value), (key: Key, value: Value)) throws -> Bool
    ) rethrows -> (key: Key, value: Value)? {
        try storage.min(by: areInIncreasingOrder)
    }

    @inlinable
    public func max(
        by areInIncreasingOrder: @Sendable ((key: Key, value: Value), (key: Key, value: Value)) throws -> Bool
    ) rethrows -> (key: Key, value: Value)? {
        try storage.max(by: areInIncreasingOrder)
    }

    @inlinable
    public func randomElement() -> (key: Key, value: Value)? {
        storage.randomElement()
    }

    @inlinable
    public func allSatisfy(_ predicate: @Sendable ((key: Key, value: Value)) throws -> Bool) rethrows -> Bool {
        try storage.allSatisfy(predicate)
    }

    @inlinable
    public func compactMap<T: Sendable>(_ transform: @Sendable ((key: Key, value: Value)) throws -> T?) rethrows -> [T] {
        try storage.compactMap(transform)
    }

    @inlinable
    public func sorted(
        by areInIncreasingOrder: @Sendable ((key: Key, value: Value), (key: Key, value: Value)) throws -> Bool
    ) rethrows -> [(key: Key, value: Value)] {
        try storage.sorted(by: areInIncreasingOrder)
    }

    @inlinable
    public func map<T: Sendable>(_ transform: @Sendable ((key: Key, value: Value)) throws -> T) rethrows -> [T] {
        try storage.map(transform)
    }

    @inlinable
    public func forEach(_ body: @Sendable ((key: Key, value: Value)) throws -> Void) rethrows {
        try storage.forEach(body)
    }

    @inlinable
    public func reduce<Result: Sendable>(
        into initial: Result,
        _ updateAccumulatingResult: @Sendable (inout Result, (key: Key, value: Value)) throws -> Void
    ) rethrows -> Result {
        try storage.reduce(into: initial, updateAccumulatingResult)
    }

    @inlinable
    public func reduce<Result: Sendable>(
        _ initialResult: Result,
        _ nextPartialResult: @Sendable (Result, (key: Key, value: Value)) throws -> Result
    ) rethrows -> Result {
        try storage.reduce(initialResult, nextPartialResult)
    }

    @inlinable
    public subscript(key: Key) -> Value? {
        storage[key]
    }

    /// `d[k, default: 0] += 1` isn't expressible here — an actor's subscript can't be assigned or
    /// modified from outside the actor, so this is get-only, mirroring `subscript(key:)` above.
    /// For an atomic default-and-update, use `mutate`: `await dict.mutate { $0[k, default: 0] += 1 }`.
    @inlinable
    public subscript(key: Key, default defaultValue: @autoclosure @Sendable () -> Value) -> Value {
        storage[key, default: defaultValue()]
    }

    /// Runs `body` as a single unit of work isolated to this actor, so compound
    /// operations (check-then-act, multi-step updates) are atomic — not just each individual call.
    @inlinable
    public func mutate<T>(_ body: (inout [Key: Value]) throws -> T) rethrows -> T {
        try body(&storage)
    }
}
