import Foundation
import Testing
@testable import ThreadSafeKit

private let mechanisms: [ThreadSafeMechanism] = [.lock, .dispatchQueue]

@Test(arguments: mechanisms) func threadSafeArrayAppendAndRead(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe<[Int]>(mechanism: mechanism)
    array.append(1)
    array.append(2)
    #expect(array.count == 2)
    #expect(array[0] == 1)
    #expect(array.pop() == 2)
}

@Test(arguments: mechanisms) func threadSafeArrayInitWithSequence(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe([1, 2, 3], mechanism: mechanism)
    #expect(array.elements == [1, 2, 3])
}

@Test(arguments: mechanisms) func threadSafeArrayIsEmptyFirstLast(mechanism: ThreadSafeMechanism) throws {
    let empty = ThreadSafe<[Int]>(mechanism: mechanism)
    #expect(empty.isEmpty)
    #expect(empty.first == nil)
    #expect(empty.last == nil)

    let array = ThreadSafe([1, 2, 3], mechanism: mechanism)
    #expect(array.isEmpty == false)
    #expect(array.first == 1)
    #expect(array.last == 3)
}

@Test(arguments: mechanisms) func threadSafeArrayPush(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe([2, 3], mechanism: mechanism)
    array.push(1)
    #expect(array.elements == [1, 2, 3])
}

@Test(arguments: mechanisms) func threadSafeArrayRemoveAt(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe([1, 2, 3], mechanism: mechanism)
    let removed = array.remove(at: 1)
    #expect(removed == 2)
    #expect(array.elements == [1, 3])
}

@Test(arguments: mechanisms) func threadSafeArrayRemoveAll(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe([1, 2, 3], mechanism: mechanism)
    array.removeAll()
    #expect(array.isEmpty)
}

@Test(arguments: mechanisms) func threadSafeArrayForEach(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe([1, 2, 3], mechanism: mechanism)
    let sum = ThreadSafe(wrappedValue: 0)
    array.forEach { element in sum.mutate { $0 += element } }
    #expect(sum.wrappedValue == 6)
}

@Test(arguments: mechanisms) func threadSafeArrayMap(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe([1, 2, 3], mechanism: mechanism)
    let doubled = array.map { $0 * 2 }
    #expect(doubled == [2, 4, 6])
}

@Test(arguments: mechanisms) func threadSafeArraySubscriptSafe(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe([1, 2, 3], mechanism: mechanism)
    #expect(array[safe: 0] == 1)
    #expect(array[safe: 3] == nil)
}

@Test(arguments: mechanisms) func threadSafeArraySubscriptSet(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe([1, 2, 3], mechanism: mechanism)
    array[1] = 20
    #expect(array.elements == [1, 20, 3])
}

@Test(arguments: mechanisms) func threadSafeArrayConcurrentAppendsDoNotDropWrites(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe<[Int]>(mechanism: mechanism)
    DispatchQueue.concurrentPerform(iterations: concurrencyIterations) { i in
        array.append(i)
    }
    #expect(array.count == concurrencyIterations)
}

// Interleaves reads with writes to exercise the backing mechanism specifically: whether it's the
// unfair lock (all access exclusive) or the concurrent queue + barrier (concurrent readers, exclusive
// writers), concurrent readers and writers still can't race. A real race here is caught by Thread
// Sanitizer (`swift test --sanitize=thread`), not just by a dropped-write count.
@Test(arguments: mechanisms) func threadSafeArrayConcurrentReadsDuringWritesDoNotRace(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe<[Int]>(mechanism: mechanism)
    DispatchQueue.concurrentPerform(iterations: concurrencyIterations * 2) { i in
        if i % 2 == 0 {
            array.append(i)
        } else {
            _ = array.count
            _ = array.elements
            _ = array.first
            _ = array.last
            _ = array[safe: 0]
        }
    }
    #expect(array.count == concurrencyIterations)
}

@Test(arguments: mechanisms) func threadSafeArrayMutateReturnsValueAndMutates(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe([1, 2, 3], mechanism: mechanism)
    let sum = array.mutate { elements in
        let total = elements.reduce(0, +)
        elements.append(total)
        return total
    }
    #expect(sum == 6)
    #expect(array.elements == [1, 2, 3, 6])
}

// Each iteration reads the current count then appends it (check-then-act). If `mutate`
// didn't hold the lock/queue for the whole closure, two iterations could read the same
// count and append duplicate values, leaving gaps/dupes instead of a clean permutation of 0..<N.
@Test(arguments: mechanisms) func threadSafeArrayMutateIsAtomicAcrossCompoundOperations(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe<[Int]>(mechanism: mechanism)
    DispatchQueue.concurrentPerform(iterations: concurrencyIterations) { _ in
        array.mutate { elements in
            elements.append(elements.count)
        }
    }
    #expect(array.elements.sorted() == Array(0..<concurrencyIterations))
}

// Demonstrates the exact problem `mutate` fixes: reading `count` then appending
// as two separate lock/queue acquisitions lets both reads observe the same stale count,
// producing a duplicate instead of a clean sequence. A single `mutate` call
// doesn't have this problem because both steps happen under one acquisition.
@Test(arguments: mechanisms) func threadSafeArraySeparateCountAndAppendCanProduceDuplicates(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe<[Int]>(mechanism: mechanism)
    let countA = array.count
    let countB = array.count
    array.append(countA)
    array.append(countB)
    #expect(array.elements == [0, 0])
}

@Test(arguments: mechanisms) func threadSafeArrayCodableRoundTrip(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe(["a", "b", "c"], mechanism: mechanism)
    let data = try JSONEncoder().encode(array)
    let decoded = try JSONDecoder().decode(ThreadSafe<[String]>.self, from: data)
    #expect(decoded.elements == ["a", "b", "c"])
}

// Auto-synthesized Codable on a containing type only compiles because
// ThreadSafe<[String]> conforms to Codable; this is the whole point of the feature.
@Test func threadSafeArrayCodableRoundTripInsideContainingType() throws {
    struct Container: Codable {
        let items: ThreadSafe<[String]>
    }
    let container = Container(items: ThreadSafe(["x", "y"]))
    let data = try JSONEncoder().encode(container)
    let decoded = try JSONDecoder().decode(Container.self, from: data)
    #expect(decoded.items.elements == ["x", "y"])
}

@Test func threadSafeArrayEquatableComparesElements() throws {
    #expect(ThreadSafe([1, 2, 3]) == ThreadSafe([1, 2, 3]))
    #expect(ThreadSafe([1, 2, 3]) != ThreadSafe([1, 2]))
    #expect(ThreadSafe([1, 2, 3]) != ThreadSafe([3, 2, 1]))
}

// Auto-synthesized Equatable on a containing type only compiles because
// ThreadSafe<[Int]> conforms to Equatable; this is the whole point of the feature.
@Test func threadSafeArrayEquatableInsideContainingType() throws {
    struct Container: Equatable {
        let items: ThreadSafe<[Int]>
    }
    #expect(Container(items: ThreadSafe([1, 2])) == Container(items: ThreadSafe([1, 2])))
    #expect(Container(items: ThreadSafe([1, 2])) != Container(items: ThreadSafe([1, 3])))
}

@Test(arguments: mechanisms) func threadSafeArrayDescriptionContainsElements(mechanism: ThreadSafeMechanism) throws {
    #expect(ThreadSafe([1, 2, 3], mechanism: mechanism).description == "ThreadSafe([1, 2, 3])")
}

@Test(arguments: mechanisms) func threadSafeArrayPropertyWrapperReadsSnapshotAndProjectsInstance(mechanism: ThreadSafeMechanism) throws {
    @ThreadSafe(mechanism: mechanism) var items = [1, 2, 3]
    #expect(items == [1, 2, 3])
    $items.append(4)
    #expect(items == [1, 2, 3, 4])
    #expect($items.count == 4)
}
