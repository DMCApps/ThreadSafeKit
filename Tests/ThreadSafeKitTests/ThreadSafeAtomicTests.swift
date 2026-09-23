import Foundation
import Testing
@testable import ThreadSafeKit

private let mechanisms: [ThreadSafeMechanism] = [.lock, .dispatchQueue]

@Test(arguments: mechanisms) func threadSafeAtomicMutatesUnderLockOrQueue(mechanism: ThreadSafeMechanism) throws {
    @ThreadSafeAtomic(mechanism: mechanism) var counter = 0
    _counter.mutate { $0 += 1 }
    #expect(counter == 1)
}

@Test(arguments: mechanisms) func threadSafeAtomicWrappedValueGetMutate(mechanism: ThreadSafeMechanism) throws {
    @ThreadSafeAtomic(mechanism: mechanism) var value = 1
    _value.mutate { $0 = 2 }
    #expect(value == 2)
}

@Test(arguments: mechanisms) func threadSafeAtomicConcurrentMutationsDoNotDropWrites(mechanism: ThreadSafeMechanism) throws {
    let counter = ThreadSafeAtomic(wrappedValue: 0, mechanism: mechanism)
    DispatchQueue.concurrentPerform(iterations: concurrencyIterations) { _ in
        counter.mutate { $0 += 1 }
    }
    #expect(counter.wrappedValue == concurrencyIterations)
}

// Demonstrates the exact problem `mutate` fixes: reading and writing as two
// separate lock/queue acquisitions lets a stale read clobber a concurrent write, even
// though each individual call is itself atomic. A single `mutate` call doesn't
// have this problem because both steps happen under one acquisition.
@Test(arguments: mechanisms) func threadSafeAtomicSeparateGetAndMutateCanLoseUpdates(mechanism: ThreadSafeMechanism) throws {
    let counter = ThreadSafeAtomic(wrappedValue: 0, mechanism: mechanism)
    let a = counter.wrappedValue
    let b = counter.wrappedValue
    counter.mutate { $0 = a + 1 }
    counter.mutate { $0 = b + 1 }
    #expect(counter.wrappedValue == 1)
}

@Test(arguments: mechanisms) func threadSafeAtomicCodableRoundTrip(mechanism: ThreadSafeMechanism) throws {
    let counter = ThreadSafeAtomic(wrappedValue: 42, mechanism: mechanism)
    let data = try JSONEncoder().encode(counter)
    let decoded = try JSONDecoder().decode(ThreadSafeAtomic<Int>.self, from: data)
    #expect(decoded.wrappedValue == 42)
}

// Auto-synthesized Codable on a containing type only compiles because
// ThreadSafeAtomic<Int> conforms to Codable; this is the whole point of the feature.
@Test func threadSafeAtomicCodableRoundTripInsideContainingType() throws {
    struct Container: Codable {
        let counter: ThreadSafeAtomic<Int>
    }
    let container = Container(counter: ThreadSafeAtomic(wrappedValue: 7))
    let data = try JSONEncoder().encode(container)
    let decoded = try JSONDecoder().decode(Container.self, from: data)
    #expect(decoded.counter.wrappedValue == 7)
}

@Test func threadSafeAtomicEquatableComparesWrappedValue() throws {
    #expect(ThreadSafeAtomic(wrappedValue: 1) == ThreadSafeAtomic(wrappedValue: 1))
    #expect(ThreadSafeAtomic(wrappedValue: 1) != ThreadSafeAtomic(wrappedValue: 2))
}

// Auto-synthesized Equatable on a containing type only compiles because
// ThreadSafeAtomic<Int> conforms to Equatable; this is the whole point of the feature.
@Test func threadSafeAtomicEquatableInsideContainingType() throws {
    struct Container: Equatable {
        let counter: ThreadSafeAtomic<Int>
    }
    #expect(Container(counter: ThreadSafeAtomic(wrappedValue: 1)) == Container(counter: ThreadSafeAtomic(wrappedValue: 1)))
    #expect(Container(counter: ThreadSafeAtomic(wrappedValue: 1)) != Container(counter: ThreadSafeAtomic(wrappedValue: 2)))
}

@Test func threadSafeAtomicHashableUsableInSet() throws {
    let set: Set<ThreadSafeAtomic<Int>> = [
        ThreadSafeAtomic(wrappedValue: 1), ThreadSafeAtomic(wrappedValue: 1), ThreadSafeAtomic(wrappedValue: 2),
    ]
    #expect(set.count == 2)
}

@Test(arguments: mechanisms) func threadSafeAtomicDescriptionContainsWrappedValue(mechanism: ThreadSafeMechanism) throws {
    #expect(ThreadSafeAtomic(wrappedValue: 42, mechanism: mechanism).description == "ThreadSafeAtomic(42)")
}
