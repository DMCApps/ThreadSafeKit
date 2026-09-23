import Foundation
import Testing
@testable import ThreadSafeKit

@Test func atomicQueueMutatesUnderQueue() throws {
    @AtomicQueue var counter = 0
    _counter.mutate { $0 += 1 }
    #expect(counter == 1)
}

@Test func atomicQueueWrappedValueGetMutate() throws {
    @AtomicQueue var value = 1
    _value.mutate { $0 = 2 }
    #expect(value == 2)
}

@Test func atomicQueueConcurrentMutationsDoNotDropWrites() throws {
    let counter = AtomicQueue(wrappedValue: 0)
    DispatchQueue.concurrentPerform(iterations: concurrencyIterations) { _ in
        counter.mutate { $0 += 1 }
    }
    #expect(counter.wrappedValue == concurrencyIterations)
}

// Demonstrates the exact problem `mutate` fixes: reading and writing as two
// separate queue syncs lets a stale read clobber a concurrent write, even
// though each individual call is itself atomic. A single `mutate` call doesn't
// have this problem because both steps happen under one queue sync.
@Test func atomicQueueSeparateGetAndMutateCanLoseUpdates() throws {
    let counter = AtomicQueue(wrappedValue: 0)
    let a = counter.wrappedValue
    let b = counter.wrappedValue
    counter.mutate { $0 = a + 1 }
    counter.mutate { $0 = b + 1 }
    #expect(counter.wrappedValue == 1)
}

@Test func atomicQueueCodableRoundTrip() throws {
    let counter = AtomicQueue(wrappedValue: 42)
    let data = try JSONEncoder().encode(counter)
    let decoded = try JSONDecoder().decode(AtomicQueue<Int>.self, from: data)
    #expect(decoded.wrappedValue == 42)
}

// Auto-synthesized Codable on a containing type only compiles because
// AtomicQueue<Int> conforms to Codable; this is the whole point of the feature.
@Test func atomicQueueCodableRoundTripInsideContainingType() throws {
    struct Container: Codable {
        let counter: AtomicQueue<Int>
    }
    let container = Container(counter: AtomicQueue(wrappedValue: 7))
    let data = try JSONEncoder().encode(container)
    let decoded = try JSONDecoder().decode(Container.self, from: data)
    #expect(decoded.counter.wrappedValue == 7)
}

@Test func atomicQueueEquatableComparesWrappedValue() throws {
    #expect(AtomicQueue(wrappedValue: 1) == AtomicQueue(wrappedValue: 1))
    #expect(AtomicQueue(wrappedValue: 1) != AtomicQueue(wrappedValue: 2))
}

// Auto-synthesized Equatable on a containing type only compiles because
// AtomicQueue<Int> conforms to Equatable; this is the whole point of the feature.
@Test func atomicQueueEquatableInsideContainingType() throws {
    struct Container: Equatable {
        let counter: AtomicQueue<Int>
    }
    #expect(Container(counter: AtomicQueue(wrappedValue: 1)) == Container(counter: AtomicQueue(wrappedValue: 1)))
    #expect(Container(counter: AtomicQueue(wrappedValue: 1)) != Container(counter: AtomicQueue(wrappedValue: 2)))
}

@Test func atomicQueueHashableUsableInSet() throws {
    let set: Set<AtomicQueue<Int>> = [AtomicQueue(wrappedValue: 1), AtomicQueue(wrappedValue: 1), AtomicQueue(wrappedValue: 2)]
    #expect(set.count == 2)
}
