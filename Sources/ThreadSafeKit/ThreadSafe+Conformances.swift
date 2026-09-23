extension ThreadSafe: CustomStringConvertible {
    public var description: String {
        "ThreadSafe(\(wrappedValue))"
    }
}

extension ThreadSafe: Equatable where Value: Equatable {
    public static func == (lhs: ThreadSafe, rhs: ThreadSafe) -> Bool {
        lhs.wrappedValue == rhs.wrappedValue
    }
}

extension ThreadSafe: Hashable where Value: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(wrappedValue)
    }
}

extension ThreadSafe: Codable where Value: Codable {
    public convenience init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(wrappedValue: try container.decode(Value.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}
