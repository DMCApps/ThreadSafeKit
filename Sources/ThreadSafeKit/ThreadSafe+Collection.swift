extension ThreadSafe where Value: Collection, Value.Element: Sendable {
    public var count: Int { read { $0.count } }
    public var isEmpty: Bool { read { $0.isEmpty } }

    public func forEach(_ body: @Sendable (Value.Element) throws -> Void) rethrows {
        try read { try $0.forEach(body) }
    }

    public func map<T: Sendable>(_ transform: @Sendable (Value.Element) throws -> T) rethrows -> [T] {
        try read { try $0.map(transform) }
    }

    public func reduce<Result: Sendable>(
        into initial: Result,
        _ updateAccumulatingResult: @Sendable (inout Result, Value.Element) throws -> Void
    ) rethrows -> Result {
        try read { try $0.reduce(into: initial, updateAccumulatingResult) }
    }
}

extension ThreadSafe where Value: Collection, Value.Element: Sendable, Value.Index: Sendable {
    public subscript(safe index: Value.Index) -> Value.Element? {
        read { $0.indices.contains(index) ? $0[index] : nil }
    }
}

// `first`/`last` live here (BidirectionalCollection), not on the general Collection extension above,
// so a dictionary shape — Collection but not BidirectionalCollection — doesn't advertise a
// nondeterministic `first`.
extension ThreadSafe where Value: BidirectionalCollection, Value.Element: Sendable {
    public var first: Value.Element? { read { $0.first } }
    public var last: Value.Element? { read { $0.last } }
}
