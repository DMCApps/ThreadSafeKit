public actor ArrayActor<Element: Sendable> {
    private var storage: [Element]

    public init() {
        storage = []
    }

    public init(_ elements: some Sequence<Element>) {
        storage = Array(elements)
    }

    public var count: Int {
        storage.count
    }

    public var isEmpty: Bool {
        storage.isEmpty
    }

    public var first: Element? {
        storage.first
    }

    public var last: Element? {
        storage.last
    }

    public var elements: [Element] {
        storage
    }

    public func append(_ newElement: Element) {
        storage.append(newElement)
    }

    public func push(_ newElement: Element) {
        storage.insert(newElement, at: 0)
    }

    public func pop() -> Element? {
        storage.popLast()
    }

    @discardableResult
    public func remove(at index: Int) -> Element {
        storage.remove(at: index)
    }

    public func removeAll(keepingCapacity keepCapacity: Bool = false) {
        storage.removeAll(keepingCapacity: keepCapacity)
    }

    public func forEach(_ body: @Sendable (Element) throws -> Void) rethrows {
        try storage.forEach(body)
    }

    public func map<T: Sendable>(_ transform: @Sendable (Element) throws -> T) rethrows -> [T] {
        try storage.map(transform)
    }

    public subscript(index: Int) -> Element {
        storage[index]
    }

    public func setElement(_ newValue: Element, at index: Int) {
        storage[index] = newValue
    }

    public subscript(safe index: Int) -> Element? {
        storage.indices.contains(index) ? storage[index] : nil
    }
}
