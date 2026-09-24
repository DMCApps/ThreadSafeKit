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

// Deliberately not Hashable: hash(into:) forwarding to wrappedValue's live, mutable contents
// would violate Hashable's contract the moment a member is mutated after being inserted into a
// Set/Dictionary key position — Set never re-buckets an existing member, so its hash must never
// change while it's a member. Value types (Array/Dictionary/String/...) get this for free via
// copy-on-write (a stored copy can't be reached and mutated by anyone); ThreadSafe is a
// reference type whose entire purpose is shared, in-place mutation, so no hash derived from its
// content can stay stable for a member's whole lifetime. Equatable above has no such invariant to
// violate (== is just an ad hoc snapshot comparison, nothing stores the result), so it's safe to
// keep. To deduplicate/hash by content, snapshot first: `Set(instances.map(\.wrappedValue))`.
