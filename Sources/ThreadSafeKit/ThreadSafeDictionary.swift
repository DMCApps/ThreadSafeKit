public actor ThreadSafeDictionary<Key: Hashable & Sendable, Value: Sendable> {
    private var storage: [Key: Value]

    public init(_ dictionary: [Key: Value] = [:]) {
        storage = dictionary
    }

    public var count: Int {
        storage.count
    }

    public var isEmpty: Bool {
        storage.isEmpty
    }

    public var dictionary: [Key: Value] {
        storage
    }

    public var keys: Dictionary<Key, Value>.Keys {
        storage.keys
    }

    public var values: Dictionary<Key, Value>.Values {
        storage.values
    }

    @discardableResult
    public func removeValue(forKey key: Key) -> Value? {
        storage.removeValue(forKey: key)
    }

    @discardableResult
    public func updateValue(_ value: Value, forKey key: Key) -> Value? {
        storage.updateValue(value, forKey: key)
    }

    public func removeAll(keepingCapacity keepCapacity: Bool = false) {
        storage.removeAll(keepingCapacity: keepCapacity)
    }

    public func popFirst() -> (key: Key, value: Value)? {
        storage.popFirst()
    }

    public func reserveCapacity(_ minimumCapacity: Int) {
        storage.reserveCapacity(minimumCapacity)
    }

    public func merge(_ other: [Key: Value], uniquingKeysWith combine: @Sendable (Value, Value) throws -> Value) rethrows {
        try storage.merge(other, uniquingKeysWith: combine)
    }

    /// The sequence-of-pairs overload, alongside the whole-dictionary one above.
    public func merge(
        _ other: some Sequence<(Key, Value)> & Sendable,
        uniquingKeysWith combine: @Sendable (Value, Value) throws -> Value
    ) rethrows {
        try storage.merge(other, uniquingKeysWith: combine)
    }

    public func mapValues<T: Sendable>(_ transform: @Sendable (Value) throws -> T) rethrows -> [Key: T] {
        try storage.mapValues(transform)
    }

    public func compactMapValues<T: Sendable>(_ transform: @Sendable (Value) throws -> T?) rethrows -> [Key: T] {
        try storage.compactMapValues(transform)
    }

    public func filter(_ isIncluded: @Sendable ((key: Key, value: Value)) throws -> Bool) rethrows -> [Key: Value] {
        try storage.filter(isIncluded)
    }

    public func contains(where predicate: @Sendable ((key: Key, value: Value)) throws -> Bool) rethrows -> Bool {
        try storage.contains(where: predicate)
    }

    public func first(where predicate: @Sendable ((key: Key, value: Value)) throws -> Bool) rethrows -> (key: Key, value: Value)? {
        try storage.first(where: predicate)
    }

    public func count(where predicate: @Sendable ((key: Key, value: Value)) throws -> Bool) rethrows -> Int {
        try storage.count(where: predicate)
    }

    public func min(
        by areInIncreasingOrder: @Sendable ((key: Key, value: Value), (key: Key, value: Value)) throws -> Bool
    ) rethrows -> (key: Key, value: Value)? {
        try storage.min(by: areInIncreasingOrder)
    }

    public func max(
        by areInIncreasingOrder: @Sendable ((key: Key, value: Value), (key: Key, value: Value)) throws -> Bool
    ) rethrows -> (key: Key, value: Value)? {
        try storage.max(by: areInIncreasingOrder)
    }

    public func randomElement() -> (key: Key, value: Value)? {
        storage.randomElement()
    }

    public func allSatisfy(_ predicate: @Sendable ((key: Key, value: Value)) throws -> Bool) rethrows -> Bool {
        try storage.allSatisfy(predicate)
    }

    public func compactMap<T: Sendable>(_ transform: @Sendable ((key: Key, value: Value)) throws -> T?) rethrows -> [T] {
        try storage.compactMap(transform)
    }

    public func sorted(
        by areInIncreasingOrder: @Sendable ((key: Key, value: Value), (key: Key, value: Value)) throws -> Bool
    ) rethrows -> [(key: Key, value: Value)] {
        try storage.sorted(by: areInIncreasingOrder)
    }

    public func map<T: Sendable>(_ transform: @Sendable ((key: Key, value: Value)) throws -> T) rethrows -> [T] {
        try storage.map(transform)
    }

    public func forEach(_ body: @Sendable ((key: Key, value: Value)) throws -> Void) rethrows {
        try storage.forEach(body)
    }

    public func reduce<Result: Sendable>(
        into initial: Result,
        _ updateAccumulatingResult: @Sendable (inout Result, (key: Key, value: Value)) throws -> Void
    ) rethrows -> Result {
        try storage.reduce(into: initial, updateAccumulatingResult)
    }

    public func reduce<Result: Sendable>(
        _ initialResult: Result,
        _ nextPartialResult: @Sendable (Result, (key: Key, value: Value)) throws -> Result
    ) rethrows -> Result {
        try storage.reduce(initialResult, nextPartialResult)
    }

    public subscript(key: Key) -> Value? {
        storage[key]
    }

    /// `d[k, default: 0] += 1` isn't expressible here — an actor's subscript can't be assigned or
    /// modified from outside the actor, so this is get-only, mirroring `subscript(key:)` above.
    /// For an atomic default-and-update, use `mutate`: `await dict.mutate { $0[k, default: 0] += 1 }`.
    public subscript(key: Key, default defaultValue: @autoclosure @Sendable () -> Value) -> Value {
        storage[key, default: defaultValue()]
    }

    /// Runs `body` as a single unit of work isolated to this actor, so compound
    /// operations (check-then-act, multi-step updates) are atomic — not just each individual call.
    public func mutate<T>(_ body: (inout [Key: Value]) throws -> T) rethrows -> T {
        try body(&storage)
    }
}
