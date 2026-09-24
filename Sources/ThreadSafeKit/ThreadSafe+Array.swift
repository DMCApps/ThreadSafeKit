extension ThreadSafe where Value: RangeReplaceableCollection, Value.Element: Sendable {
    @inlinable
    public convenience init(mechanism: ThreadSafeMechanism = .readerWriterLock) {
        self.init(wrappedValue: Value(), mechanism: mechanism)
    }

    @inlinable
    public convenience init(
        _ elements: some Sequence<Value.Element>,
        mechanism: ThreadSafeMechanism = .readerWriterLock
    ) {
        self.init(wrappedValue: Value(elements), mechanism: mechanism)
    }

    @inlinable
    public var elements: Value { read { $0 } }

    @inlinable
    public func append(_ newElement: Value.Element) {
        write { $0.append(newElement) }
    }

    @inlinable
    public func append(contentsOf newElements: some Sequence<Value.Element> & Sendable) {
        write { $0.append(contentsOf: newElements) }
    }

    @inlinable
    public func removeAll(keepingCapacity keepCapacity: Bool = false) {
        write { $0.removeAll(keepingCapacity: keepCapacity) }
    }

    @inlinable
    public func removeAll(where shouldBeRemoved: @Sendable (Value.Element) throws -> Bool) rethrows {
        try write { try $0.removeAll(where: shouldBeRemoved) }
    }

    @discardableResult
    @inlinable
    public func removeFirst() -> Value.Element {
        write { $0.removeFirst() }
    }

    @inlinable
    public func removeFirst(_ n: Int) {
        write { $0.removeFirst(n) }
    }

    @inlinable
    public func reserveCapacity(_ n: Int) {
        write { $0.reserveCapacity(n) }
    }

    @inlinable
    public func filter(_ isIncluded: @Sendable (Value.Element) throws -> Bool) rethrows -> [Value.Element] {
        try read { try $0.filter(isIncluded) }
    }

    @inlinable
    public func compactMap<T: Sendable>(_ transform: @Sendable (Value.Element) throws -> T?) rethrows -> [T] {
        try read { try $0.compactMap(transform) }
    }

    @inlinable
    public func sorted(by areInIncreasingOrder: @Sendable (Value.Element, Value.Element) throws -> Bool) rethrows -> [Value.Element] {
        try read { try $0.sorted(by: areInIncreasingOrder) }
    }

    @inlinable
    public func allSatisfy(_ predicate: @Sendable (Value.Element) throws -> Bool) rethrows -> Bool {
        try read { try $0.allSatisfy(predicate) }
    }

    @inlinable
    public func prefix(_ maxLength: Int) -> [Value.Element] {
        read { Array($0.prefix(maxLength)) }
    }

    @inlinable
    public func suffix(_ maxLength: Int) -> [Value.Element] {
        read { Array($0.suffix(maxLength)) }
    }
}

extension ThreadSafe where Value: RangeReplaceableCollection, Value.Element: Sendable & Equatable {
    @inlinable
    public func contains(_ element: Value.Element) -> Bool {
        read { $0.contains(element) }
    }
}

extension ThreadSafe where Value: RangeReplaceableCollection, Value.Element: Sendable & Comparable {
    @inlinable
    public func sorted() -> [Value.Element] {
        read { $0.sorted() }
    }

    @inlinable
    public func min() -> Value.Element? {
        read { $0.min() }
    }

    @inlinable
    public func max() -> Value.Element? {
        read { $0.max() }
    }
}

extension ThreadSafe where Value: RangeReplaceableCollection, Value.Element: Sendable, Value.Index: Sendable {
    @discardableResult
    @inlinable
    public func remove(at index: Value.Index) -> Value.Element {
        write { $0.remove(at: index) }
    }

    @inlinable
    public func insert(_ newElement: Value.Element, at index: Value.Index) {
        write { $0.insert(newElement, at: index) }
    }

    @inlinable
    public func insert(contentsOf newElements: some Collection<Value.Element> & Sendable, at index: Value.Index) {
        write { $0.insert(contentsOf: newElements, at: index) }
    }

    @inlinable
    public func removeSubrange(_ bounds: Range<Value.Index>) {
        write { $0.removeSubrange(bounds) }
    }

    @inlinable
    public func replaceSubrange<C: Collection & Sendable>(
        _ subrange: Range<Value.Index>,
        with newElements: C
    ) where C.Element == Value.Element {
        write { $0.replaceSubrange(subrange, with: newElements) }
    }

    @inlinable
    public func firstIndex(where predicate: @Sendable (Value.Element) throws -> Bool) rethrows -> Value.Index? {
        try read { try $0.firstIndex(where: predicate) }
    }
}

extension ThreadSafe
where Value: RangeReplaceableCollection, Value.Element: Sendable & Equatable, Value.Index: Sendable {
    @inlinable
    public func firstIndex(of element: Value.Element) -> Value.Index? {
        read { $0.firstIndex(of: element) }
    }
}

extension ThreadSafe
where Value: RangeReplaceableCollection & BidirectionalCollection, Value.Element: Sendable {
    @inlinable
    public func popLast() -> Value.Element? {
        write { $0.popLast() }
    }

    @discardableResult
    @inlinable
    public func removeLast() -> Value.Element {
        write { $0.removeLast() }
    }

    @inlinable
    public func removeLast(_ n: Int) {
        write { $0.removeLast(n) }
    }
}

extension ThreadSafe where Value: MutableCollection, Value.Element: Sendable, Value.Index: Sendable {
    /// Atomic for the whole access, including compound forms like `ts[i] += 1` and
    /// `ts[i]?.append(x)` — the write lock is held across the entire get-modify-set. Note that
    /// `ts[i] = ts[i] + 1` is two separate accesses (a `get`, then a `_modify`), so it's NOT
    /// atomic; use `+=` or `mutate` for that.
    @inlinable
    public subscript(index: Value.Index) -> Value.Element {
        get { read { $0[index] } }
        _modify {
            beginModify()
            defer { endModify() }
            yield &storage[index]
        }
    }
}

extension ThreadSafe where Value: MutableCollection & BidirectionalCollection, Value.Element: Sendable {
    @inlinable
    public func reverse() {
        write { $0.reverse() }
    }
}

extension ThreadSafe where Value: MutableCollection & RandomAccessCollection, Value.Element: Sendable {
    @inlinable
    public func sort(by areInIncreasingOrder: @Sendable (Value.Element, Value.Element) throws -> Bool) rethrows {
        try write { try $0.sort(by: areInIncreasingOrder) }
    }

    @inlinable
    public func shuffle() {
        write { $0.shuffle() }
    }
}

extension ThreadSafe where Value: MutableCollection & RandomAccessCollection, Value.Element: Sendable & Comparable {
    @inlinable
    public func sort() {
        write { $0.sort() }
    }
}
