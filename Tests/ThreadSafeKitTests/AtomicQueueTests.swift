import Foundation
import Testing
@testable import ThreadSafeKit

@Test func atomicQueueMutatesUnderQueue() throws {
    @AtomicQueue var counter = 0
    _counter.mutate { $0 += 1 }
    #expect(counter == 1)
}

@Test func atomicQueueWrappedValueGetSet() throws {
    @AtomicQueue var value = 1
    value = 2
    #expect(value == 2)
}

@Test func atomicQueueConcurrentMutationsDoNotDropWrites() throws {
    let counter = AtomicQueue(wrappedValue: 0)
    DispatchQueue.concurrentPerform(iterations: concurrencyIterations) { _ in
        counter.mutate { $0 += 1 }
    }
    #expect(counter.wrappedValue == concurrencyIterations)
}
