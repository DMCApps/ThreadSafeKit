import Foundation
import Testing
@testable import ThreadSafeKit

@Test func arrayLockAppendAndRead() throws {
    let array = ArrayLock<Int>()
    array.append(1)
    array.append(2)
    #expect(array.count == 2)
    #expect(array[0] == 1)
    #expect(array.pop() == 2)
}

@Test func arrayLockInitWithSequence() throws {
    let array = ArrayLock([1, 2, 3])
    #expect(array.elements == [1, 2, 3])
}

@Test func arrayLockIsEmptyFirstLast() throws {
    let empty = ArrayLock<Int>()
    #expect(empty.isEmpty)
    #expect(empty.first == nil)
    #expect(empty.last == nil)

    let array = ArrayLock([1, 2, 3])
    #expect(array.isEmpty == false)
    #expect(array.first == 1)
    #expect(array.last == 3)
}

@Test func arrayLockPush() throws {
    let array = ArrayLock([2, 3])
    array.push(1)
    #expect(array.elements == [1, 2, 3])
}

@Test func arrayLockRemoveAt() throws {
    let array = ArrayLock([1, 2, 3])
    let removed = array.remove(at: 1)
    #expect(removed == 2)
    #expect(array.elements == [1, 3])
}

@Test func arrayLockRemoveAll() throws {
    let array = ArrayLock([1, 2, 3])
    array.removeAll()
    #expect(array.isEmpty)
}

@Test func arrayLockForEach() throws {
    let array = ArrayLock([1, 2, 3])
    let sum = Atomic(wrappedValue: 0)
    array.forEach { element in sum.mutate { $0 += element } }
    #expect(sum.wrappedValue == 6)
}

@Test func arrayLockMap() throws {
    let array = ArrayLock([1, 2, 3])
    let doubled = array.map { $0 * 2 }
    #expect(doubled == [2, 4, 6])
}

@Test func arrayLockSubscriptSafe() throws {
    let array = ArrayLock([1, 2, 3])
    #expect(array[safe: 0] == 1)
    #expect(array[safe: 3] == nil)
}

@Test func arrayLockSubscriptSet() throws {
    let array = ArrayLock([1, 2, 3])
    array[1] = 20
    #expect(array.elements == [1, 20, 3])
}

@Test func arrayLockConcurrentAppendsDoNotDropWrites() throws {
    let array = ArrayLock<Int>()
    DispatchQueue.concurrentPerform(iterations: concurrencyIterations) { i in
        array.append(i)
    }
    #expect(array.count == concurrencyIterations)
}

// Interleaves reads with writes to exercise the lock specifically: all access
// is exclusive, so concurrent readers and writers still can't race. A real
// race here is caught by Thread Sanitizer (`swift test --sanitize=thread`),
// not just by a dropped-write count.
@Test func arrayLockConcurrentReadsDuringWritesDoNotRace() throws {
    let array = ArrayLock<Int>()
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

@Test func arrayLockMutateReturnsValueAndMutates() throws {
    let array = ArrayLock([1, 2, 3])
    let sum = array.mutate { elements in
        let total = elements.reduce(0, +)
        elements.append(total)
        return total
    }
    #expect(sum == 6)
    #expect(array.elements == [1, 2, 3, 6])
}

// Each iteration reads the current count then appends it (check-then-act). If `mutate`
// didn't hold the lock for the whole closure, two iterations could read the same
// count and append duplicate values, leaving gaps/dupes instead of a clean permutation of 0..<N.
@Test func arrayLockMutateIsAtomicAcrossCompoundOperations() throws {
    let array = ArrayLock<Int>()
    DispatchQueue.concurrentPerform(iterations: concurrencyIterations) { _ in
        array.mutate { elements in
            elements.append(elements.count)
        }
    }
    #expect(array.elements.sorted() == Array(0..<concurrencyIterations))
}

// Demonstrates the exact problem `mutate` fixes: reading `count` then appending
// as two separate lock acquisitions lets both reads observe the same stale count,
// producing a duplicate instead of a clean sequence. A single `mutate` call
// doesn't have this problem because both steps happen under one lock acquisition.
@Test func arrayLockSeparateCountAndAppendCanProduceDuplicates() throws {
    let array = ArrayLock<Int>()
    let countA = array.count
    let countB = array.count
    array.append(countA)
    array.append(countB)
    #expect(array.elements == [0, 0])
}

@Test func arrayLockCodableRoundTrip() throws {
    let array = ArrayLock(["a", "b", "c"])
    let data = try JSONEncoder().encode(array)
    let decoded = try JSONDecoder().decode(ArrayLock<String>.self, from: data)
    #expect(decoded.elements == ["a", "b", "c"])
}

// Auto-synthesized Codable on a containing type only compiles because
// ArrayLock<String> conforms to Codable; this is the whole point of the feature.
@Test func arrayLockCodableRoundTripInsideContainingType() throws {
    struct Container: Codable {
        let items: ArrayLock<String>
    }
    let container = Container(items: ArrayLock(["x", "y"]))
    let data = try JSONEncoder().encode(container)
    let decoded = try JSONDecoder().decode(Container.self, from: data)
    #expect(decoded.items.elements == ["x", "y"])
}

@Test func arrayLockEquatableComparesElements() throws {
    #expect(ArrayLock([1, 2, 3]) == ArrayLock([1, 2, 3]))
    #expect(ArrayLock([1, 2, 3]) != ArrayLock([1, 2]))
    #expect(ArrayLock([1, 2, 3]) != ArrayLock([3, 2, 1]))
}

// Auto-synthesized Equatable on a containing type only compiles because
// ArrayLock<Int> conforms to Equatable; this is the whole point of the feature.
@Test func arrayLockEquatableInsideContainingType() throws {
    struct Container: Equatable {
        let items: ArrayLock<Int>
    }
    #expect(Container(items: ArrayLock([1, 2])) == Container(items: ArrayLock([1, 2])))
    #expect(Container(items: ArrayLock([1, 2])) != Container(items: ArrayLock([1, 3])))
}

@Test func arrayLockHashableUsableInSet() throws {
    let set: Set<ArrayLock<Int>> = [ArrayLock([1, 2]), ArrayLock([1, 2]), ArrayLock([3])]
    #expect(set.count == 2)
}

@Test func arrayLockDescriptionContainsElements() throws {
    #expect(ArrayLock([1, 2, 3]).description == "ArrayLock([1, 2, 3])")
}
