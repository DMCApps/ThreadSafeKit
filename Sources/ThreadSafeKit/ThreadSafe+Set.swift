extension ThreadSafe where Value: SetAlgebra, Value.Element: Sendable {
    @inlinable
    public convenience init(mechanism: ThreadSafeMechanism = .readerWriterLock) {
        self.init(wrappedValue: Value(), mechanism: mechanism)
    }

    @inlinable
    public var elements: Value { read { $0 } }

    @inlinable
    public func contains(_ member: Value.Element) -> Bool {
        read { $0.contains(member) }
    }

    @discardableResult
    @inlinable
    public func insert(_ newMember: Value.Element) -> (inserted: Bool, memberAfterInsert: Value.Element) {
        write { $0.insert(newMember) }
    }

    @discardableResult
    @inlinable
    public func remove(_ member: Value.Element) -> Value.Element? {
        write { $0.remove(member) }
    }

    @discardableResult
    @inlinable
    public func update(with newMember: Value.Element) -> Value.Element? {
        write { $0.update(with: newMember) }
    }

    // `SetAlgebra` has no generic `removeAll(keepingCapacity:)` (that's a `RangeReplaceableCollection`
    // API `Set` also happens to have, but not every `SetAlgebra` conformer does) — `init()` is the one
    // reset operation the protocol itself guarantees, so use that directly instead of requiring a
    // Set-specific extension.
    @inlinable
    public func removeAll() {
        write { $0 = Value() }
    }

    @inlinable
    public func union(_ other: Value) -> Value {
        read { $0.union(other) }
    }

    @inlinable
    public func intersection(_ other: Value) -> Value {
        read { $0.intersection(other) }
    }

    @inlinable
    public func symmetricDifference(_ other: Value) -> Value {
        read { $0.symmetricDifference(other) }
    }

    @inlinable
    public func formUnion(_ other: Value) {
        write { $0.formUnion(other) }
    }

    @inlinable
    public func formIntersection(_ other: Value) {
        write { $0.formIntersection(other) }
    }

    @inlinable
    public func subtract(_ other: Value) {
        write { $0.subtract(other) }
    }

    @inlinable
    public func formSymmetricDifference(_ other: Value) {
        write { $0.formSymmetricDifference(other) }
    }

    @inlinable
    public func isSubset(of other: Value) -> Bool {
        read { $0.isSubset(of: other) }
    }

    @inlinable
    public func isSuperset(of other: Value) -> Bool {
        read { $0.isSuperset(of: other) }
    }

    @inlinable
    public func isDisjoint(with other: Value) -> Bool {
        read { $0.isDisjoint(with: other) }
    }

    @inlinable
    public func isStrictSubset(of other: Value) -> Bool {
        read { $0.isStrictSubset(of: other) }
    }

    @inlinable
    public func isStrictSuperset(of other: Value) -> Bool {
        read { $0.isStrictSuperset(of: other) }
    }
}
