import Foundation
import Testing
@testable import ThreadSafeKit

@Test func setActorInsertAndContains() async throws {
    let set = ThreadSafeSet<Int>()
    await set.insert(1)
    await set.insert(2)
    #expect(await set.count == 2)
    #expect(await set.contains(1))
    #expect(await set.contains(3) == false)
}

@Test func setActorInitWithSequence() async throws {
    let set = ThreadSafeSet([1, 2, 3])
    #expect(await set.elements == [1, 2, 3])
}

@Test func setActorIsEmpty() async throws {
    let empty = ThreadSafeSet<Int>()
    #expect(await empty.isEmpty)

    let set = ThreadSafeSet([1])
    #expect(await set.isEmpty == false)
}

@Test func setActorInsertReturnsInsertedAndMember() async throws {
    let set = ThreadSafeSet([1])
    let first = await set.insert(1)
    #expect(first.inserted == false)
    #expect(first.memberAfterInsert == 1)

    let second = await set.insert(2)
    #expect(second.inserted)
    #expect(second.memberAfterInsert == 2)
}

@Test func setActorRemove() async throws {
    let set = ThreadSafeSet([1, 2, 3])
    let removed = await set.remove(2)
    #expect(removed == 2)
    #expect(await set.elements == [1, 3])
    #expect(await set.remove(2) == nil)
}

@Test func setActorRemoveAll() async throws {
    let set = ThreadSafeSet([1, 2, 3])
    await set.removeAll()
    #expect(await set.isEmpty)
}

@Test func setActorUpdateWith() async throws {
    let set = ThreadSafeSet([1, 2])
    #expect(await set.update(with: 1) == 1)
    #expect(await set.update(with: 3) == nil)
    #expect(await set.elements == [1, 2, 3])
}

@Test func setActorUnionIntersectionSymmetricDifference() async throws {
    let set = ThreadSafeSet([1, 2, 3])
    #expect(await set.union([3, 4]) == [1, 2, 3, 4])
    #expect(await set.intersection([2, 3, 4]) == [2, 3])
    #expect(await set.symmetricDifference([2, 3, 4]) == [1, 4])
    #expect(await set.elements == [1, 2, 3])
}

@Test func setActorFormUnion() async throws {
    let set = ThreadSafeSet([1, 2])
    await set.formUnion([2, 3])
    #expect(await set.elements == [1, 2, 3])
}

@Test func setActorFormIntersection() async throws {
    let set = ThreadSafeSet([1, 2, 3])
    await set.formIntersection([2, 3, 4])
    #expect(await set.elements == [2, 3])
}

@Test func setActorSubtract() async throws {
    let set = ThreadSafeSet([1, 2, 3])
    await set.subtract([2])
    #expect(await set.elements == [1, 3])
}

@Test func setActorFormSymmetricDifference() async throws {
    let set = ThreadSafeSet([1, 2, 3])
    await set.formSymmetricDifference([2, 3, 4])
    #expect(await set.elements == [1, 4])
}

@Test func setActorSubsetSupersetDisjoint() async throws {
    let set = ThreadSafeSet([1, 2])
    #expect(await set.isSubset(of: [1, 2, 3]))
    #expect(await set.isSuperset(of: [1]))
    #expect(await set.isDisjoint(with: [3, 4]))
    #expect(await set.isStrictSubset(of: [1, 2, 3]))
    #expect(await set.isStrictSubset(of: [1, 2]) == false)
    #expect(await set.isStrictSuperset(of: [1]))
    #expect(await set.isStrictSuperset(of: [1, 2]) == false)
}

@Test func setActorForEach() async throws {
    let set = ThreadSafeSet([1, 2, 3])
    let sum = ThreadSafe(wrappedValue: 0)
    await set.forEach { element in sum.mutate { $0 += element } }
    #expect(sum.wrappedValue == 6)
}

@Test func setActorMap() async throws {
    let set = ThreadSafeSet([1, 2, 3])
    let doubled = await set.map { $0 * 2 }
    #expect(Set(doubled) == [2, 4, 6])
}

@Test func setActorConcurrentInsertsDoNotDropWrites() async throws {
    let set = ThreadSafeSet<Int>()
    await withTaskGroup(of: Void.self) { group in
        for i in 0..<concurrencyIterations {
            group.addTask { await set.insert(i) }
        }
    }
    #expect(await set.count == concurrencyIterations)
}

// Mixed concurrent reads and writes must not corrupt state; run under TSan to catch races.
@Test func setActorConcurrentReadsDuringWritesDoNotRace() async throws {
    let set = ThreadSafeSet<Int>()
    await withTaskGroup(of: Void.self) { group in
        for i in 0..<(concurrencyIterations * 2) {
            group.addTask {
                if i % 2 == 0 {
                    await set.insert(i)
                } else {
                    _ = await set.count
                    _ = await set.elements
                    _ = await set.contains(0)
                }
            }
        }
    }
    #expect(await set.count == concurrencyIterations)
}

@Test func setActorMutateReturnsValueAndMutates() async throws {
    let set = ThreadSafeSet([1, 2, 3])
    let sum = await set.mutate { members -> Int in
        let total = members.reduce(0, +)
        members.insert(total)
        return total
    }
    #expect(sum == 6)
    #expect(await set.elements == [1, 2, 3, 6])
}

@Test func setActorSubtracting() async throws {
    let set = ThreadSafeSet([1, 2, 3])
    #expect(await set.subtracting([2, 3]) == [1])
    #expect(await set.elements == [1, 2, 3])
}

@Test func setActorPopFirst() async throws {
    let set = ThreadSafeSet([1])
    #expect(await set.popFirst() == 1)
    #expect(await set.isEmpty)

    let empty = ThreadSafeSet<Int>()
    #expect(await empty.popFirst() == nil)
}

// Concurrent drains must remove every element exactly once — no duplicates, no drops.
@Test func setActorConcurrentPopFirstDrainsExactlyOnce() async throws {
    let n = 2_000
    let set = ThreadSafeSet(0..<n)
    let popped = ThreadSafeArray<Int>()
    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<8 {
            group.addTask {
                while let value = await set.popFirst() {
                    await popped.append(value)
                }
            }
        }
    }
    #expect(await set.isEmpty)
    let drained = await popped.elements
    #expect(drained.count == n)
    #expect(Set(drained) == Set(0..<n))
}

@Test func setActorRemoveFirst() async throws {
    let set = ThreadSafeSet([1])
    #expect(await set.removeFirst() == 1)
    #expect(await set.isEmpty)
}

// `removeFirst()` traps when empty, so call it once per seeded element.
@Test func setActorConcurrentRemoveFirstDrainsExactlyOnce() async throws {
    let n = 2_000
    let set = ThreadSafeSet(0..<n)
    let removed = ThreadSafeArray<Int>()
    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<n {
            group.addTask {
                let value = await set.removeFirst()
                await removed.append(value)
            }
        }
    }
    #expect(await set.isEmpty)
    let drained = await removed.elements
    #expect(drained.count == n)
    #expect(Set(drained) == Set(0..<n))
}

@Test func setActorReserveCapacity() async throws {
    let set = ThreadSafeSet([1, 2, 3])
    await set.reserveCapacity(100)
    #expect(await set.elements == [1, 2, 3])
}

// Concurrent `reserveCapacity` must not drop concurrent inserts.
@Test func setActorConcurrentReserveCapacityDoesNotCorruptConcurrentInserts() async throws {
    let set = ThreadSafeSet<Int>()
    let n = concurrencyIterations
    await withTaskGroup(of: Void.self) { group in
        for i in 0..<n {
            group.addTask { await set.insert(i) }
        }
        for _ in 0..<n {
            group.addTask { await set.reserveCapacity(1_000) }
        }
    }
    #expect(await set.count == n)
    #expect(await set.elements == Set(0..<n))
}

@Test func setActorRemoveAllKeepingCapacity() async throws {
    let set = ThreadSafeSet([1, 2, 3])
    await set.removeAll(keepingCapacity: true)
    #expect(await set.isEmpty)
}

// Every call empties the set and inserts are >= n, so no seed value can survive.
@Test func setActorRemoveAllKeepingCapacityConcurrentWithInsertsNeverLeavesSeedValues() async throws {
    let n = 600
    let k = 4
    let set = ThreadSafeSet(0..<n)
    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<k {
            group.addTask {
                for _ in 0..<100 { await set.removeAll(keepingCapacity: true) }
            }
        }
        for w in 0..<k {
            group.addTask {
                for j in 0..<100 { await set.insert(n + w * 100 + j) }
            }
        }
    }
    let remaining = await set.elements
    #expect(remaining.isDisjoint(with: Set(0..<n)))
    #expect(remaining.isSubset(of: Set(n..<(n + k * 100))))
}

@Test func setActorFilterReturnsSet() async throws {
    let set = ThreadSafeSet([1, 2, 3, 4])
    let evens: Set<Int> = await set.filter { $0 % 2 == 0 }
    #expect(evens == [2, 4])
}

@Test func setActorFirstWhere() async throws {
    let set = ThreadSafeSet([1, 2, 3])
    #expect(await set.first(where: { $0 == 2 }) == 2)
    #expect(await set.first(where: { $0 == 4 }) == nil)
}

@Test func setActorContainsWhere() async throws {
    let set = ThreadSafeSet([1, 2, 3])
    #expect(await set.contains(where: { $0 == 2 }) == true)
    #expect(await set.contains(where: { $0 == 4 }) == false)
}

@Test func setActorCountWhere() async throws {
    let set = ThreadSafeSet([1, 2, 3, 4])
    #expect(await set.count(where: { $0 % 2 == 0 }) == 2)
}

@Test func setActorMinByAndMaxBy() async throws {
    let set = ThreadSafeSet([3, 1, 2])
    #expect(await set.min(by: <) == 1)
    #expect(await set.max(by: <) == 3)
}

@Test func setActorReduceNonInto() async throws {
    let set = ThreadSafeSet([1, 2, 3, 4])
    let sum = await set.reduce(0, +)
    #expect(sum == 10)
}

@Test func setActorReduceInto() async throws {
    let set = ThreadSafeSet([1, 2, 3, 4])
    let sum = await set.reduce(into: 0) { $0 += $1 }
    #expect(sum == 10)
}

@Test func setActorRandomElement() async throws {
    let set = ThreadSafeSet([1, 2, 3])
    let element = await set.randomElement()
    #expect([1, 2, 3].contains(element!))

    let empty = ThreadSafeSet<Int>()
    #expect(await empty.randomElement() == nil)
}

@Test func setActorAllSatisfy() async throws {
    let set = ThreadSafeSet([2, 4, 6])
    #expect(await set.allSatisfy { $0 % 2 == 0 })
    #expect(await set.allSatisfy { $0 > 2 } == false)
}

@Test func setActorCompactMap() async throws {
    let set = ThreadSafeSet([1, 2, 3, 4])
    #expect(Set(await set.compactMap { $0 % 2 == 0 ? $0 : nil }) == [2, 4])
}

@Test func setActorSortedBy() async throws {
    let set = ThreadSafeSet([3, 1, 2])
    #expect(await set.sorted(by: >) == [3, 2, 1])
}

@Test func setActorSortedMinMax() async throws {
    let set = ThreadSafeSet([3, 1, 2])
    #expect(await set.sorted() == [1, 2, 3])
    #expect(await set.min() == 1)
    #expect(await set.max() == 3)
}
