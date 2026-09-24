import Foundation
import Testing
@testable import ThreadSafeKit

private let mechanisms: [ThreadSafeMechanism] = [.lock, .readerWriterLock]

@Test(arguments: mechanisms) func threadSafeAtomicMutatesUnderLockOrQueue(mechanism: ThreadSafeMechanism) throws {
    @ThreadSafe(mechanism: mechanism) var counter = 0
    _counter.mutate { $0 += 1 }
    #expect(counter == 1)
}

@Test(arguments: mechanisms) func threadSafeAtomicWrappedValueGetMutate(mechanism: ThreadSafeMechanism) throws {
    @ThreadSafe(mechanism: mechanism) var value = 1
    _value.mutate { $0 = 2 }
    #expect(value == 2)
}

@Test(arguments: mechanisms) func threadSafeAtomicConcurrentMutationsDoNotDropWrites(mechanism: ThreadSafeMechanism) throws {
    let counter = ThreadSafe(wrappedValue: 0, mechanism: mechanism)
    DispatchQueue.concurrentPerform(iterations: concurrencyIterations) { _ in
        counter.mutate { $0 += 1 }
    }
    #expect(counter.wrappedValue == concurrencyIterations)
}

@Test func threadSafeAtomicEquatableComparesWrappedValue() throws {
    #expect(ThreadSafe(wrappedValue: 1) == ThreadSafe(wrappedValue: 1))
    #expect(ThreadSafe(wrappedValue: 1) != ThreadSafe(wrappedValue: 2))
}

// Auto-synthesized Equatable on a containing type only compiles because
// ThreadSafe<Int> conforms to Equatable; this is the whole point of the feature.
@Test func threadSafeAtomicEquatableInsideContainingType() throws {
    struct Container: Equatable {
        let counter: ThreadSafe<Int>
    }
    #expect(Container(counter: ThreadSafe(wrappedValue: 1)) == Container(counter: ThreadSafe(wrappedValue: 1)))
    #expect(Container(counter: ThreadSafe(wrappedValue: 1)) != Container(counter: ThreadSafe(wrappedValue: 2)))
}

@Test(arguments: mechanisms) func threadSafeAtomicDescriptionContainsWrappedValue(mechanism: ThreadSafeMechanism) throws {
    #expect(ThreadSafe(wrappedValue: 42, mechanism: mechanism).description == "ThreadSafe(42)")
}
