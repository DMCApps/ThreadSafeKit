extension ThreadSafe where Value: RangeReplaceableCollection, Value.Element: Sendable {
    public convenience init(mechanism: ThreadSafeMechanism = .dispatchQueue) {
        self.init(wrappedValue: Value(), mechanism: mechanism)
    }

    public convenience init(
        _ elements: some Sequence<Value.Element>,
        mechanism: ThreadSafeMechanism = .dispatchQueue
    ) {
        self.init(wrappedValue: Value(elements), mechanism: mechanism)
    }

    public var elements: Value { read { $0 } }

    public func append(_ newElement: Value.Element) {
        write { $0.append(newElement) }
    }

    public func push(_ newElement: Value.Element) {
        write { $0.insert(newElement, at: $0.startIndex) }
    }

    public func removeAll(keepingCapacity keepCapacity: Bool = false) {
        write { $0.removeAll(keepingCapacity: keepCapacity) }
    }
}

extension ThreadSafe where Value: RangeReplaceableCollection, Value.Element: Sendable, Value.Index: Sendable {
    @discardableResult
    public func remove(at index: Value.Index) -> Value.Element {
        write { $0.remove(at: index) }
    }
}

extension ThreadSafe
where Value: RangeReplaceableCollection & BidirectionalCollection, Value.Element: Sendable {
    public func pop() -> Value.Element? {
        write { $0.popLast() }
    }
}

extension ThreadSafe where Value: MutableCollection, Value.Element: Sendable, Value.Index: Sendable {
    public subscript(index: Value.Index) -> Value.Element {
        get { read { $0[index] } }
        set { write { $0[index] = newValue } }
    }
}
