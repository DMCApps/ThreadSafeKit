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
