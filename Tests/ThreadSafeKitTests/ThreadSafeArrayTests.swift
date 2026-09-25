import Foundation
import Testing
@testable import ThreadSafeKit

private let mechanisms: [ThreadSafeMechanism] = [.lock, .readerWriterLock]

@Test(arguments: mechanisms) func threadSafeArrayAppendAndRead(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe<[Int]>(mechanism: mechanism)
    array.append(1)
    array.append(2)
    #expect(array.count == 2)
    #expect(array[0] == 1)
    #expect(array.popLast() == 2)
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

@Test(arguments: mechanisms) func threadSafeArrayRemoveAllWhereRemovesMatchesKeepsOrder(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe([1, 2, 3, 4, 5, 6], mechanism: mechanism)
    array.removeAll(where: { $0 % 2 == 0 })
    #expect(array.elements == [1, 3, 5])
}

@Test(arguments: mechanisms) func threadSafeArrayRemoveAllWhereNoMatchesLeavesArrayUnchanged(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe([1, 3, 5], mechanism: mechanism)
    array.removeAll(where: { $0 % 2 == 0 })
    #expect(array.elements == [1, 3, 5])
}

@Test(arguments: mechanisms) func threadSafeArrayRemoveAllWhereAllMatchesEmptiesArray(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe([2, 4, 6], mechanism: mechanism)
    array.removeAll(where: { $0 % 2 == 0 })
    #expect(array.isEmpty)
}

@Test(arguments: mechanisms) func threadSafeArrayRemoveAllWhereOnEmptyArrayIsNoOp(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe<[Int]>(mechanism: mechanism)
    array.removeAll(where: { _ in true })
    #expect(array.isEmpty)
}

private struct RemoveAllBoom: Error {}

// `removeAll(where:)` may reorder before throwing, so only count and contents are asserted.
@Test(arguments: mechanisms) func threadSafeArrayRemoveAllWhereReleasesLockWhenPredicateThrows(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe([1, 2, 3, 4, 5, 6], mechanism: mechanism)
    #expect(throws: RemoveAllBoom.self) {
        try array.removeAll { value in
            if value == 4 { throw RemoveAllBoom() }
            return false
        }
    }
    #expect(array.count == 6)
    #expect(Set(array.elements) == Set([1, 2, 3, 4, 5, 6]))
    // Follow-up access proves the lock was released.
    array.append(7)
    #expect(array.count == 7)
}

// Every original value must be removed and every concurrently appended value kept.
@Test(arguments: mechanisms) func threadSafeArrayRemoveAllWhereConcurrentWithAppendsIsExact(mechanism: ThreadSafeMechanism) throws {
    let n = 600
    let k = 4
    let array = ThreadSafe(Array(0..<n), mechanism: mechanism)
    DispatchQueue.concurrentPerform(iterations: k * 2) { i in
        if i < k {
            let r = i
            array.removeAll { $0 >= 0 && $0 < n && $0 % k == r }
        } else {
            for j in 0..<100 { array.append(n + (i - k) * 100 + j) }
        }
    }
    let remaining = Set(array.elements)
    #expect(remaining.isDisjoint(with: Set(0..<n)))
    #expect(remaining.isSuperset(of: Set(n..<(n + k * 100))))
}

@Test(arguments: mechanisms) func threadSafeArrayInsertAt(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe([1, 3], mechanism: mechanism)
    array.insert(2, at: 1)
    #expect(array.elements == [1, 2, 3])
}

@Test(arguments: mechanisms) func threadSafeArrayAppendContentsOf(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe([1], mechanism: mechanism)
    array.append(contentsOf: [2, 3])
    #expect(array.elements == [1, 2, 3])
}

@Test(arguments: mechanisms) func threadSafeArrayInsertContentsOfAt(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe([1, 4], mechanism: mechanism)
    array.insert(contentsOf: [2, 3], at: 1)
    #expect(array.elements == [1, 2, 3, 4])
}

@Test(arguments: mechanisms) func threadSafeArrayRemoveFirst(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe([1, 2, 3], mechanism: mechanism)
    #expect(array.removeFirst() == 1)
    #expect(array.elements == [2, 3])
}

@Test(arguments: mechanisms) func threadSafeArrayRemoveFirstN(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe([1, 2, 3], mechanism: mechanism)
    array.removeFirst(2)
    #expect(array.elements == [3])
}

@Test(arguments: mechanisms) func threadSafeArrayRemoveLast(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe([1, 2, 3], mechanism: mechanism)
    #expect(array.removeLast() == 3)
    #expect(array.elements == [1, 2])
}

@Test(arguments: mechanisms) func threadSafeArrayRemoveLastN(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe([1, 2, 3], mechanism: mechanism)
    array.removeLast(2)
    #expect(array.elements == [1])
}

@Test(arguments: mechanisms) func threadSafeArrayRemoveSubrange(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe([1, 2, 3, 4], mechanism: mechanism)
    array.removeSubrange(1..<3)
    #expect(array.elements == [1, 4])
}

@Test(arguments: mechanisms) func threadSafeArrayReplaceSubrange(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe([1, 2, 3], mechanism: mechanism)
    array.replaceSubrange(1..<2, with: [20, 30])
    #expect(array.elements == [1, 20, 30, 3])
}

@Test(arguments: mechanisms) func threadSafeArrayReserveCapacity(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe([1, 2, 3], mechanism: mechanism)
    array.reserveCapacity(100)
    #expect(array.elements == [1, 2, 3])
}

@Test(arguments: mechanisms) func threadSafeArrayReverse(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe([1, 2, 3], mechanism: mechanism)
    array.reverse()
    #expect(array.elements == [3, 2, 1])
}

@Test(arguments: mechanisms) func threadSafeArraySort(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe([3, 1, 2], mechanism: mechanism)
    array.sort()
    #expect(array.elements == [1, 2, 3])
}

@Test(arguments: mechanisms) func threadSafeArraySortBy(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe([1, 2, 3], mechanism: mechanism)
    array.sort(by: >)
    #expect(array.elements == [3, 2, 1])
}

@Test(arguments: mechanisms) func threadSafeArrayShuffleKeepsSameElements(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe([1, 2, 3, 4, 5], mechanism: mechanism)
    array.shuffle()
    #expect(array.elements.sorted() == [1, 2, 3, 4, 5])
}

@Test(arguments: mechanisms) func threadSafeArrayFirstIndexWhere(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe([1, 2, 3], mechanism: mechanism)
    #expect(array.firstIndex(where: { $0 == 2 }) == 1)
    #expect(array.firstIndex(where: { $0 == 4 }) == nil)
}

@Test(arguments: mechanisms) func threadSafeArrayFirstIndexOf(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe([1, 2, 3], mechanism: mechanism)
    #expect(array.firstIndex(of: 2) == 1)
    #expect(array.firstIndex(of: 4) == nil)
}

@Test(arguments: mechanisms) func threadSafeArrayContains(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe([1, 2, 3], mechanism: mechanism)
    #expect(array.contains(2))
    #expect(array.contains(4) == false)
}

@Test(arguments: mechanisms) func threadSafeArrayFilter(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe([1, 2, 3, 4], mechanism: mechanism)
    #expect(array.filter { $0 % 2 == 0 } == [2, 4])
}

@Test(arguments: mechanisms) func threadSafeArrayCompactMap(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe([1, 2, 3, 4], mechanism: mechanism)
    #expect(array.compactMap { $0 % 2 == 0 ? $0 : nil } == [2, 4])
}

@Test(arguments: mechanisms) func threadSafeArraySortedAndSortedBy(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe([3, 1, 2], mechanism: mechanism)
    #expect(array.sorted() == [1, 2, 3])
    #expect(array.sorted(by: >) == [3, 2, 1])
    #expect(array.elements == [3, 1, 2])
}

@Test(arguments: mechanisms) func threadSafeArrayMinAndMax(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe([3, 1, 2], mechanism: mechanism)
    #expect(array.min() == 1)
    #expect(array.max() == 3)
}

@Test(arguments: mechanisms) func threadSafeArrayAllSatisfy(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe([2, 4, 6], mechanism: mechanism)
    #expect(array.allSatisfy { $0 % 2 == 0 })
    #expect(array.allSatisfy { $0 > 2 } == false)
}

@Test(arguments: mechanisms) func threadSafeArrayPrefixAndSuffix(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe([1, 2, 3, 4], mechanism: mechanism)
    #expect(array.prefix(2) == [1, 2])
    #expect(array.suffix(2) == [3, 4])
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

// `array[0] += 1` holds the write lock across get-modify-set, so no increments are lost.
@Test(arguments: mechanisms) func threadSafeArraySubscriptCompoundAssignmentIsAtomic(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe([0], mechanism: mechanism)
    let workers = 8
    let perWorker = 250
    DispatchQueue.concurrentPerform(iterations: workers) { _ in
        for _ in 0..<perWorker { array[0] += 1 }
    }
    #expect(array[0] == workers * perWorker)
}

// Concurrent subscript writes must not change the count seen by readers.
@Test(arguments: mechanisms) func threadSafeArraySubscriptAssignmentIsSafeAlongsideConcurrentReaders(mechanism: ThreadSafeMechanism) throws {
    let writerCount = 8
    let array = ThreadSafe(Array(0..<writerCount), mechanism: mechanism)
    DispatchQueue.concurrentPerform(iterations: writerCount * 2) { i in
        if i < writerCount {
            for value in 0..<1_000 { array[i] = value }
        } else {
            for _ in 0..<1_000 {
                #expect(array.elements.count == writerCount, "concurrent subscript assignment corrupted array size")
            }
        }
    }
    #expect(array.count == writerCount)
}

private struct BumpError: Error {}

private extension Int {
    mutating func bumpOrThrow() throws {
        self += 1
        throw BumpError()
    }
}

// `_modify`'s `defer` must release the write lock when the mutation throws.
@Test(arguments: mechanisms) func threadSafeArraySubscriptModifyReleasesLockWhenMutatingCallThrows(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe([0], mechanism: mechanism)
    #expect(throws: BumpError.self) {
        try array[0].bumpOrThrow()
    }
    // Mutation before the throw is kept; `_modify` isn't transactional.
    #expect(array[0] == 1)
    // Follow-up access proves the lock was released.
    array[0] += 1
    #expect(array[0] == 2)
}

@Test(arguments: mechanisms) func threadSafeArrayConcurrentAppendsDoNotDropWrites(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe<[Int]>(mechanism: mechanism)
    DispatchQueue.concurrentPerform(iterations: concurrencyIterations) { i in
        array.append(i)
    }
    #expect(array.count == concurrencyIterations)
}

// Mixed concurrent reads and writes must not corrupt state; run under TSan to catch races.
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

// Check-then-act inside `mutate` must yield a clean permutation of 0..<N.
@Test(arguments: mechanisms) func threadSafeArrayMutateIsAtomicAcrossCompoundOperations(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe<[Int]>(mechanism: mechanism)
    DispatchQueue.concurrentPerform(iterations: concurrencyIterations) { _ in
        array.mutate { elements in
            elements.append(elements.count)
        }
    }
    #expect(array.elements.sorted() == Array(0..<concurrencyIterations))
}

@Test func threadSafeArrayEquatableComparesElements() throws {
    #expect(ThreadSafe([1, 2, 3]) == ThreadSafe([1, 2, 3]))
    #expect(ThreadSafe([1, 2, 3]) != ThreadSafe([1, 2]))
    #expect(ThreadSafe([1, 2, 3]) != ThreadSafe([3, 2, 1]))
}

// Compiles only because `ThreadSafe<[Int]>` is Equatable.
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

@Test(arguments: mechanisms) func threadSafeArraySwapAt(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe([1, 2, 3], mechanism: mechanism)
    array.swapAt(0, 2)
    #expect(array.elements == [3, 2, 1])
}

// An even number of swaps must restore the original order.
@Test(arguments: mechanisms) func threadSafeArrayConcurrentSwapAtNeverLosesElements(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe([0, 1], mechanism: mechanism)
    DispatchQueue.concurrentPerform(iterations: 8) { _ in
        for _ in 0..<250 { array.swapAt(0, 1) }
    }
    #expect(array.elements == [0, 1])
}

@Test(arguments: mechanisms) func threadSafeArrayFirstWhere(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe([1, 2, 3, 4], mechanism: mechanism)
    #expect(array.first(where: { $0 % 2 == 0 }) == 2)
    #expect(array.first(where: { $0 > 10 }) == nil)
}

@Test(arguments: mechanisms) func threadSafeArrayContainsWhere(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe([1, 2, 3], mechanism: mechanism)
    #expect(array.contains(where: { $0 == 2 }) == true)
    #expect(array.contains(where: { $0 == 4 }) == false)
}

@Test(arguments: mechanisms) func threadSafeArrayCountWhere(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe([1, 2, 3, 4, 5, 6], mechanism: mechanism)
    #expect(array.count(where: { $0 % 2 == 0 }) == 3)
}

@Test(arguments: mechanisms) func threadSafeArrayMinByAndMaxBy(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe([3, 1, 2], mechanism: mechanism)
    #expect(array.min(by: <) == 1)
    #expect(array.max(by: <) == 3)
}

@Test(arguments: mechanisms) func threadSafeArrayReduceNonInto(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe([1, 2, 3, 4], mechanism: mechanism)
    let sum = array.reduce(0, +)
    #expect(sum == 10)
}

@Test(arguments: mechanisms) func threadSafeArrayRandomElement(mechanism: ThreadSafeMechanism) throws {
    let array = ThreadSafe([1, 2, 3], mechanism: mechanism)
    #expect([1, 2, 3].contains(array.randomElement()!))

    let empty = ThreadSafe<[Int]>(mechanism: mechanism)
    #expect(empty.randomElement() == nil)
}
