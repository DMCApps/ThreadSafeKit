extension ThreadSafe where Value: SetAlgebra, Value.Element: Sendable {
    public convenience init(mechanism: ThreadSafeMechanism = .dispatchQueue) {
        self.init(wrappedValue: Value(), mechanism: mechanism)
    }

    public func contains(_ member: Value.Element) -> Bool {
        read { $0.contains(member) }
    }

    @discardableResult
    public func insert(_ newMember: Value.Element) -> (inserted: Bool, memberAfterInsert: Value.Element) {
        write { $0.insert(newMember) }
    }

    @discardableResult
    public func remove(_ member: Value.Element) -> Value.Element? {
        write { $0.remove(member) }
    }

    @discardableResult
    public func update(with newMember: Value.Element) -> Value.Element? {
        write { $0.update(with: newMember) }
    }

    // `SetAlgebra` has no generic `removeAll(keepingCapacity:)` (that's a `RangeReplaceableCollection`
    // API `Set` also happens to have, but not every `SetAlgebra` conformer does) — `init()` is the one
    // reset operation the protocol itself guarantees, so use that directly instead of requiring a
    // Set-specific extension.
    public func removeAll() {
        write { $0 = Value() }
    }

    public func union(_ other: Value) -> Value {
        read { $0.union(other) }
    }

    public func intersection(_ other: Value) -> Value {
        read { $0.intersection(other) }
    }

    public func symmetricDifference(_ other: Value) -> Value {
        read { $0.symmetricDifference(other) }
    }

    public func formUnion(_ other: Value) {
        write { $0.formUnion(other) }
    }

    public func formIntersection(_ other: Value) {
        write { $0.formIntersection(other) }
    }

    public func subtract(_ other: Value) {
        write { $0.subtract(other) }
    }

    public func formSymmetricDifference(_ other: Value) {
        write { $0.formSymmetricDifference(other) }
    }

    public func isSubset(of other: Value) -> Bool {
        read { $0.isSubset(of: other) }
    }

    public func isSuperset(of other: Value) -> Bool {
        read { $0.isSuperset(of: other) }
    }

    public func isDisjoint(with other: Value) -> Bool {
        read { $0.isDisjoint(with: other) }
    }

    public func isStrictSubset(of other: Value) -> Bool {
        read { $0.isStrictSubset(of: other) }
    }

    public func isStrictSuperset(of other: Value) -> Bool {
        read { $0.isStrictSuperset(of: other) }
    }
}
