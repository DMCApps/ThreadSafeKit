public actor DictionaryActor<Key: Hashable & Sendable, Value: Sendable> {
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

    public func getValue(forKey key: Key) -> Value? {
        storage[key]
    }

    public func setValue(_ value: Value?, forKey key: Key) {
        storage[key] = value
    }

    @discardableResult
    public func removeValue(forKey key: Key) -> Value? {
        storage.removeValue(forKey: key)
    }

    public func removeAll(keepingCapacity keepCapacity: Bool = false) {
        storage.removeAll(keepingCapacity: keepCapacity)
    }

    public func merge(_ other: [Key: Value], uniquingKeysWith combine: @Sendable (Value, Value) throws -> Value) rethrows {
        try storage.merge(other, uniquingKeysWith: combine)
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

    public subscript(key: Key) -> Value? {
        storage[key]
    }
}
