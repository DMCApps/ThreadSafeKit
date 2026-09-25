import Foundation
import Testing
@testable import ThreadSafeKit

@Test func arrayActorAppendAndRead() async throws {
    let array = ThreadSafeArray<Int>()
    await array.append(1)
    await array.append(2)
    #expect(await array.count == 2)
    #expect(await array[0] == 1)
    #expect(await array.popLast() == 2)
}

@Test func arrayActorInitWithSequence() async throws {
    let array = ThreadSafeArray([1, 2, 3])
    #expect(await array.elements == [1, 2, 3])
}

@Test func arrayActorIsEmptyFirstLast() async throws {
    let empty = ThreadSafeArray<Int>()
    #expect(await empty.isEmpty)
    #expect(await empty.first == nil)
    #expect(await empty.last == nil)

    let array = ThreadSafeArray([1, 2, 3])
    #expect(await array.isEmpty == false)
    #expect(await array.first == 1)
    #expect(await array.last == 3)
}

@Test func arrayActorRemoveAt() async throws {
    let array = ThreadSafeArray([1, 2, 3])
    let removed = await array.remove(at: 1)
    #expect(removed == 2)
    #expect(await array.elements == [1, 3])
}

@Test func arrayActorRemoveAll() async throws {
    let array = ThreadSafeArray([1, 2, 3])
    await array.removeAll()
    #expect(await array.isEmpty)
}

@Test func arrayActorRemoveAllWhereRemovesMatchesKeepsOrder() async throws {
    let array = ThreadSafeArray([1, 2, 3, 4, 5, 6])
    await array.removeAll(where: { $0 % 2 == 0 })
    #expect(await array.elements == [1, 3, 5])
}

@Test func arrayActorRemoveAllWhereNoMatchesLeavesArrayUnchanged() async throws {
    let array = ThreadSafeArray([1, 3, 5])
    await array.removeAll(where: { $0 % 2 == 0 })
    #expect(await array.elements == [1, 3, 5])
}

@Test func arrayActorRemoveAllWhereAllMatchesEmptiesArray() async throws {
    let array = ThreadSafeArray([2, 4, 6])
    await array.removeAll(where: { $0 % 2 == 0 })
    #expect(await array.isEmpty)
}

@Test func arrayActorRemoveAllWhereOnEmptyArrayIsNoOp() async throws {
    let array = ThreadSafeArray<Int>()
    await array.removeAll(where: { _ in true })
    #expect(await array.isEmpty)
}

private struct ArrayActorRemoveAllBoom: Error {}

// `removeAll(where:)` may reorder before throwing, so only count and contents are asserted.
@Test func arrayActorRemoveAllWhereThrowsPropagatesErrorAndKeepsPartialMutation() async throws {
    let array = ThreadSafeArray([1, 2, 3, 4, 5, 6])
    await #expect(throws: ArrayActorRemoveAllBoom.self) {
        try await array.removeAll { value in
            if value == 4 { throw ArrayActorRemoveAllBoom() }
            return false
        }
    }
    #expect(await array.count == 6)
    #expect(Set(await array.elements) == Set([1, 2, 3, 4, 5, 6]))
    // Follow-up call proves the actor is still usable.
    await array.append(7)
    #expect(await array.count == 7)
}

// Every original value must be removed and every concurrently appended value kept.
@Test func arrayActorConcurrentRemoveAllWhereAlongsideAppendsIsExact() async throws {
    let n = 600
    let k = 4
    let array = ThreadSafeArray(Array(0..<n))
    await withTaskGroup(of: Void.self) { group in
        for r in 0..<k {
            group.addTask { await array.removeAll { $0 % k == r } }
        }
        for w in 0..<k {
            group.addTask {
                for j in 0..<100 { await array.append(n + w * 100 + j) }
            }
        }
    }
    let remaining = Set(await array.elements)
    #expect(remaining.isDisjoint(with: Set(0..<n)))
    #expect(remaining.isSuperset(of: Set(n..<(n + k * 100))))
}

@Test func arrayActorInsertAt() async throws {
    let array = ThreadSafeArray([1, 3])
    await array.insert(2, at: 1)
    #expect(await array.elements == [1, 2, 3])
}

@Test func arrayActorAppendContentsOf() async throws {
    let array = ThreadSafeArray([1])
    await array.append(contentsOf: [2, 3])
    #expect(await array.elements == [1, 2, 3])
}

@Test func arrayActorInsertContentsOfAt() async throws {
    let array = ThreadSafeArray([1, 4])
    await array.insert(contentsOf: [2, 3], at: 1)
    #expect(await array.elements == [1, 2, 3, 4])
}

@Test func arrayActorRemoveFirst() async throws {
    let array = ThreadSafeArray([1, 2, 3])
    #expect(await array.removeFirst() == 1)
    #expect(await array.elements == [2, 3])
}

@Test func arrayActorRemoveFirstN() async throws {
    let array = ThreadSafeArray([1, 2, 3])
    await array.removeFirst(2)
    #expect(await array.elements == [3])
}

@Test func arrayActorRemoveLast() async throws {
    let array = ThreadSafeArray([1, 2, 3])
    #expect(await array.removeLast() == 3)
    #expect(await array.elements == [1, 2])
}

@Test func arrayActorRemoveLastN() async throws {
    let array = ThreadSafeArray([1, 2, 3])
    await array.removeLast(2)
    #expect(await array.elements == [1])
}

@Test func arrayActorRemoveSubrange() async throws {
    let array = ThreadSafeArray([1, 2, 3, 4])
    await array.removeSubrange(1..<3)
    #expect(await array.elements == [1, 4])
}

@Test func arrayActorReplaceSubrange() async throws {
    let array = ThreadSafeArray([1, 2, 3])
    await array.replaceSubrange(1..<2, with: [20, 30])
    #expect(await array.elements == [1, 20, 30, 3])
}

@Test func arrayActorReserveCapacity() async throws {
    let array = ThreadSafeArray([1, 2, 3])
    await array.reserveCapacity(100)
    #expect(await array.elements == [1, 2, 3])
}

@Test func arrayActorReverse() async throws {
    let array = ThreadSafeArray([1, 2, 3])
    await array.reverse()
    #expect(await array.elements == [3, 2, 1])
}

@Test func arrayActorSort() async throws {
    let array = ThreadSafeArray([3, 1, 2])
    await array.sort()
    #expect(await array.elements == [1, 2, 3])
}

@Test func arrayActorSortBy() async throws {
    let array = ThreadSafeArray([1, 2, 3])
    await array.sort(by: >)
    #expect(await array.elements == [3, 2, 1])
}

@Test func arrayActorShuffleKeepsSameElements() async throws {
    let array = ThreadSafeArray([1, 2, 3, 4, 5])
    await array.shuffle()
    #expect(await array.elements.sorted() == [1, 2, 3, 4, 5])
}

@Test func arrayActorFirstIndexWhere() async throws {
    let array = ThreadSafeArray([1, 2, 3])
    #expect(await array.firstIndex(where: { $0 == 2 }) == 1)
    #expect(await array.firstIndex(where: { $0 == 4 }) == nil)
}

@Test func arrayActorFirstIndexOf() async throws {
    let array = ThreadSafeArray([1, 2, 3])
    #expect(await array.firstIndex(of: 2) == 1)
    #expect(await array.firstIndex(of: 4) == nil)
}

@Test func arrayActorContains() async throws {
    let array = ThreadSafeArray([1, 2, 3])
    #expect(await array.contains(2))
    #expect(await array.contains(4) == false)
}

@Test func arrayActorFilter() async throws {
    let array = ThreadSafeArray([1, 2, 3, 4])
    #expect(await array.filter { $0 % 2 == 0 } == [2, 4])
}

@Test func arrayActorCompactMap() async throws {
    let array = ThreadSafeArray([1, 2, 3, 4])
    #expect(await array.compactMap { $0 % 2 == 0 ? $0 : nil } == [2, 4])
}

@Test func arrayActorSortedAndSortedBy() async throws {
    let array = ThreadSafeArray([3, 1, 2])
    #expect(await array.sorted() == [1, 2, 3])
    #expect(await array.sorted(by: >) == [3, 2, 1])
    #expect(await array.elements == [3, 1, 2])
}

@Test func arrayActorMinAndMax() async throws {
    let array = ThreadSafeArray([3, 1, 2])
    #expect(await array.min() == 1)
    #expect(await array.max() == 3)
}

@Test func arrayActorAllSatisfy() async throws {
    let array = ThreadSafeArray([2, 4, 6])
    #expect(await array.allSatisfy { $0 % 2 == 0 })
    #expect(await array.allSatisfy { $0 > 2 } == false)
}

@Test func arrayActorPrefixAndSuffix() async throws {
    let array = ThreadSafeArray([1, 2, 3, 4])
    #expect(await array.prefix(2) == [1, 2])
    #expect(await array.suffix(2) == [3, 4])
}

@Test func arrayActorForEach() async throws {
    let array = ThreadSafeArray([1, 2, 3])
    let sum = ThreadSafe(wrappedValue: 0)
    await array.forEach { element in sum.mutate { $0 += element } }
    #expect(sum.wrappedValue == 6)
}

@Test func arrayActorMap() async throws {
    let array = ThreadSafeArray([1, 2, 3])
    let doubled = await array.map { $0 * 2 }
    #expect(doubled == [2, 4, 6])
}

@Test func arrayActorSubscriptSafe() async throws {
    let array = ThreadSafeArray([1, 2, 3])
    #expect(await array[safe: 0] == 1)
    #expect(await array[safe: 3] == nil)
}

@Test func arrayActorSetElement() async throws {
    let array = ThreadSafeArray([1, 2, 3])
    await array.setElement(20, at: 1)
    #expect(await array.elements == [1, 20, 3])
}

@Test func arrayActorConcurrentAppendsDoNotDropWrites() async throws {
    let array = ThreadSafeArray<Int>()
    await withTaskGroup(of: Void.self) { group in
        for i in 0..<concurrencyIterations {
            group.addTask { await array.append(i) }
        }
    }
    #expect(await array.count == concurrencyIterations)
}

// Mixed concurrent reads and writes must not corrupt state; run under TSan to catch races.
@Test func arrayActorConcurrentReadsDuringWritesDoNotRace() async throws {
    let array = ThreadSafeArray<Int>()
    await withTaskGroup(of: Void.self) { group in
        for i in 0..<(concurrencyIterations * 2) {
            group.addTask {
                if i % 2 == 0 {
                    await array.append(i)
                } else {
                    _ = await array.count
                    _ = await array.elements
                    _ = await array.first
                    _ = await array.last
                    _ = await array[safe: 0]
                }
            }
        }
    }
    #expect(await array.count == concurrencyIterations)
}

@Test func arrayActorMutateReturnsValueAndMutates() async throws {
    let array = ThreadSafeArray([1, 2, 3])
    let sum = await array.mutate { elements in
        let total = elements.reduce(0, +)
        elements.append(total)
        return total
    }
    #expect(sum == 6)
    #expect(await array.elements == [1, 2, 3, 6])
}

// Check-then-act inside `mutate` must yield a clean permutation of 0..<N.
@Test func arrayActorMutateIsAtomicAcrossCompoundOperations() async throws {
    let array = ThreadSafeArray<Int>()
    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<concurrencyIterations {
            group.addTask {
                await array.mutate { elements in
                    elements.append(elements.count)
                }
            }
        }
    }
    #expect(await array.elements.sorted() == Array(0..<concurrencyIterations))
}

@Test func arrayActorSwapAt() async throws {
    let array = ThreadSafeArray([1, 2, 3])
    await array.swapAt(0, 2)
    #expect(await array.elements == [3, 2, 1])
}

// An even number of swaps must restore the original order.
@Test func arrayActorConcurrentSwapAtNeverLosesElements() async throws {
    let array = ThreadSafeArray([0, 1])
    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<8 {
            group.addTask {
                for _ in 0..<250 { await array.swapAt(0, 1) }
            }
        }
    }
    #expect(await array.elements == [0, 1])
}

@Test func arrayActorFirstWhere() async throws {
    let array = ThreadSafeArray([1, 2, 3, 4])
    #expect(await array.first(where: { $0 % 2 == 0 }) == 2)
    #expect(await array.first(where: { $0 > 10 }) == nil)
}

@Test func arrayActorContainsWhere() async throws {
    let array = ThreadSafeArray([1, 2, 3])
    #expect(await array.contains(where: { $0 == 2 }) == true)
    #expect(await array.contains(where: { $0 == 4 }) == false)
}

@Test func arrayActorCountWhere() async throws {
    let array = ThreadSafeArray([1, 2, 3, 4, 5, 6])
    #expect(await array.count(where: { $0 % 2 == 0 }) == 3)
}

@Test func arrayActorMinByAndMaxBy() async throws {
    let array = ThreadSafeArray([3, 1, 2])
    #expect(await array.min(by: <) == 1)
    #expect(await array.max(by: <) == 3)
}

@Test func arrayActorReduceNonInto() async throws {
    let array = ThreadSafeArray([1, 2, 3, 4])
    let sum = await array.reduce(0, +)
    #expect(sum == 10)
}

@Test func arrayActorReduceInto() async throws {
    let array = ThreadSafeArray([1, 2, 3, 4])
    let sum = await array.reduce(into: 0) { $0 += $1 }
    #expect(sum == 10)
}

@Test func arrayActorRandomElement() async throws {
    let array = ThreadSafeArray([1, 2, 3])
    let element = await array.randomElement()
    #expect([1, 2, 3].contains(element!))

    let empty = ThreadSafeArray<Int>()
    #expect(await empty.randomElement() == nil)
}
