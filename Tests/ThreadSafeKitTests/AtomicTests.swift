import Foundation
import Testing
@testable import ThreadSafeKit

@Test func atomicMutatesUnderLock() throws {
    @Atomic var counter = 0
    _counter.mutate { $0 += 1 }
    #expect(counter == 1)
}

@Test func atomicWrappedValueGetMutate() throws {
    @Atomic var value = 1
    _value.mutate { $0 = 2 }
    #expect(value == 2)
}

@Test func atomicConcurrentMutationsDoNotDropWrites() throws {
    let counter = Atomic(wrappedValue: 0)
    DispatchQueue.concurrentPerform(iterations: concurrencyIterations) { _ in
        counter.mutate { $0 += 1 }
    }
    #expect(counter.wrappedValue == concurrencyIterations)
}

// Demonstrates the exact problem `mutate` fixes: reading and writing as two
// separate lock acquisitions lets a stale read clobber a concurrent write, even
// though each individual call is itself atomic. A single `mutate` call doesn't
// have this problem because both steps happen under one lock acquisition.
@Test func atomicSeparateGetAndMutateCanLoseUpdates() throws {
    let counter = Atomic(wrappedValue: 0)
    let a = counter.wrappedValue
    let b = counter.wrappedValue
    counter.mutate { $0 = a + 1 }
    counter.mutate { $0 = b + 1 }
    #expect(counter.wrappedValue == 1)
}

@Test func atomicCodableRoundTrip() throws {
    let counter = Atomic(wrappedValue: 42)
    let data = try JSONEncoder().encode(counter)
    let decoded = try JSONDecoder().decode(Atomic<Int>.self, from: data)
    #expect(decoded.wrappedValue == 42)
}

// Auto-synthesized Codable on a containing type only compiles because
// Atomic<Int> conforms to Codable; this is the whole point of the feature.
@Test func atomicCodableRoundTripInsideContainingType() throws {
    struct Container: Codable {
        let counter: Atomic<Int>
    }
    let container = Container(counter: Atomic(wrappedValue: 7))
    let data = try JSONEncoder().encode(container)
    let decoded = try JSONDecoder().decode(Container.self, from: data)
    #expect(decoded.counter.wrappedValue == 7)
}

@Test func atomicEquatableComparesWrappedValue() throws {
    #expect(Atomic(wrappedValue: 1) == Atomic(wrappedValue: 1))
    #expect(Atomic(wrappedValue: 1) != Atomic(wrappedValue: 2))
}

// Auto-synthesized Equatable on a containing type only compiles because
// Atomic<Int> conforms to Equatable; this is the whole point of the feature.
@Test func atomicEquatableInsideContainingType() throws {
    struct Container: Equatable {
        let counter: Atomic<Int>
    }
    #expect(Container(counter: Atomic(wrappedValue: 1)) == Container(counter: Atomic(wrappedValue: 1)))
    #expect(Container(counter: Atomic(wrappedValue: 1)) != Container(counter: Atomic(wrappedValue: 2)))
}
