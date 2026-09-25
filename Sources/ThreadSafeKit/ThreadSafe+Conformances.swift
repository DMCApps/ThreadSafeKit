extension ThreadSafe: CustomStringConvertible {
    @inlinable
    public var description: String {
        "ThreadSafe(\(wrappedValue))"
    }
}

extension ThreadSafe: Equatable where Value: Equatable {
    @inlinable
    public static func == (lhs: ThreadSafe, rhs: ThreadSafe) -> Bool {
        lhs.wrappedValue == rhs.wrappedValue
    }
}

// Not Hashable: shared in-place mutation would change the hash of instances already in a Set or Dictionary.
