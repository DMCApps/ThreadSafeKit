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

// Interleaves reads with writes (not just writes vs writes), proving mixed
// operations don't deadlock or corrupt state under actor reentrancy. A real
// race here is caught by Thread Sanitizer (`swift test --sanitize=thread`),
// not just by a dropped-write count.
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
