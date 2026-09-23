import Foundation
import Testing
@testable import ThreadSafeKit

@Test func arrayQueueAppendAndRead() throws {
    let array = ArrayQueue<Int>()
    array.append(1)
    array.append(2)
    #expect(array.count == 2)
    #expect(array[0] == 1)
    #expect(array.pop() == 2)
}

@Test func arrayQueueInitWithSequence() throws {
    let array = ArrayQueue([1, 2, 3])
    #expect(array.elements == [1, 2, 3])
}

@Test func arrayQueueIsEmptyFirstLast() throws {
    let empty = ArrayQueue<Int>()
    #expect(empty.isEmpty)
    #expect(empty.first == nil)
    #expect(empty.last == nil)

    let array = ArrayQueue([1, 2, 3])
    #expect(array.isEmpty == false)
    #expect(array.first == 1)
    #expect(array.last == 3)
}

@Test func arrayQueuePush() throws {
    let array = ArrayQueue([2, 3])
    array.push(1)
    #expect(array.elements == [1, 2, 3])
}

@Test func arrayQueueRemoveAt() throws {
    let array = ArrayQueue([1, 2, 3])
    let removed = array.remove(at: 1)
    #expect(removed == 2)
    #expect(array.elements == [1, 3])
}

@Test func arrayQueueRemoveAll() throws {
    let array = ArrayQueue([1, 2, 3])
    array.removeAll()
    #expect(array.isEmpty)
}

@Test func arrayQueueForEach() throws {
    let array = ArrayQueue([1, 2, 3])
    var sum = 0
    array.forEach { sum += $0 }
    #expect(sum == 6)
}

@Test func arrayQueueMap() throws {
    let array = ArrayQueue([1, 2, 3])
    let doubled = array.map { $0 * 2 }
    #expect(doubled == [2, 4, 6])
}

@Test func arrayQueueSubscriptSafe() throws {
    let array = ArrayQueue([1, 2, 3])
    #expect(array[safe: 0] == 1)
    #expect(array[safe: 3] == nil)
}

@Test func arrayQueueSubscriptSet() throws {
    let array = ArrayQueue([1, 2, 3])
    array[1] = 20
    #expect(array.elements == [1, 20, 3])
}

@Test func arrayQueueConcurrentAppendsDoNotDropWrites() throws {
    let array = ArrayQueue<Int>()
    DispatchQueue.concurrentPerform(iterations: concurrencyIterations) { i in
        array.append(i)
    }
    #expect(array.count == concurrencyIterations)
}

// Interleaves reads with writes to exercise the `.concurrent` + barrier
// design specifically: concurrent readers running alongside exclusive
// writers. A real race here is caught by Thread Sanitizer
// (`swift test --sanitize=thread`), not just by a dropped-write count.
@Test func arrayQueueConcurrentReadsDuringWritesDoNotRace() throws {
    let array = ArrayQueue<Int>()
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

@Test func arrayQueueMutateReturnsValueAndMutates() throws {
    let array = ArrayQueue([1, 2, 3])
    let sum = array.mutate { elements in
        let total = elements.reduce(0, +)
        elements.append(total)
        return total
    }
    #expect(sum == 6)
    #expect(array.elements == [1, 2, 3, 6])
}

// Each iteration reads the current count then appends it (check-then-act). If `mutate`
// didn't hold the barrier lock for the whole closure, two iterations could read the same
// count and append duplicate values, leaving gaps/dupes instead of a clean permutation of 0..<N.
@Test func arrayQueueMutateIsAtomicAcrossCompoundOperations() throws {
    let array = ArrayQueue<Int>()
    DispatchQueue.concurrentPerform(iterations: concurrencyIterations) { _ in
        array.mutate { elements in
            elements.append(elements.count)
        }
    }
    #expect(array.elements.sorted() == Array(0..<concurrencyIterations))
}

// Demonstrates the exact problem `mutate` fixes: reading `count` then appending
// as two separate queue syncs lets both reads observe the same stale count,
// producing a duplicate instead of a clean sequence. A single `mutate` call
// doesn't have this problem because both steps happen under one queue sync.
@Test func arrayQueueSeparateCountAndAppendCanProduceDuplicates() throws {
    let array = ArrayQueue<Int>()
    let countA = array.count
    let countB = array.count
    array.append(countA)
    array.append(countB)
    #expect(array.elements == [0, 0])
}

@Test func arrayQueueCodableRoundTrip() throws {
    let array = ArrayQueue(["a", "b", "c"])
    let data = try JSONEncoder().encode(array)
    let decoded = try JSONDecoder().decode(ArrayQueue<String>.self, from: data)
    #expect(decoded.elements == ["a", "b", "c"])
}

// Auto-synthesized Codable on a containing type only compiles because
// ArrayQueue<String> conforms to Codable; this is the whole point of the feature.
@Test func arrayQueueCodableRoundTripInsideContainingType() throws {
    struct Container: Codable {
        let items: ArrayQueue<String>
    }
    let container = Container(items: ArrayQueue(["x", "y"]))
    let data = try JSONEncoder().encode(container)
    let decoded = try JSONDecoder().decode(Container.self, from: data)
    #expect(decoded.items.elements == ["x", "y"])
}

@Test func arrayQueueEquatableComparesElements() throws {
    #expect(ArrayQueue([1, 2, 3]) == ArrayQueue([1, 2, 3]))
    #expect(ArrayQueue([1, 2, 3]) != ArrayQueue([1, 2]))
    #expect(ArrayQueue([1, 2, 3]) != ArrayQueue([3, 2, 1]))
}

// Auto-synthesized Equatable on a containing type only compiles because
// ArrayQueue<Int> conforms to Equatable; this is the whole point of the feature.
@Test func arrayQueueEquatableInsideContainingType() throws {
    struct Container: Equatable {
        let items: ArrayQueue<Int>
    }
    #expect(Container(items: ArrayQueue([1, 2])) == Container(items: ArrayQueue([1, 2])))
    #expect(Container(items: ArrayQueue([1, 2])) != Container(items: ArrayQueue([1, 3])))
}

@Test func arrayQueueHashableUsableInSet() throws {
    let set: Set<ArrayQueue<Int>> = [ArrayQueue([1, 2]), ArrayQueue([1, 2]), ArrayQueue([3])]
    #expect(set.count == 2)
}
