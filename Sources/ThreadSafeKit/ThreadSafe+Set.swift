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

    // `SetAlgebra` has no generic `removeAll(keepingCapacity:)` (that's a `RangeReplaceableCollection`
    // API `Set` also happens to have, but not every `SetAlgebra` conformer does) — `init()` is the one
    // reset operation the protocol itself guarantees, so use that directly instead of requiring a
    // Set-specific extension.
    public func removeAll() {
        write { $0 = Value() }
    }
}
