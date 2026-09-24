import Foundation
import Testing
@testable import ThreadSafeKit

private let mechanisms: [ThreadSafeMechanism] = [.lock, .dispatchQueue, .readerWriterLock]

@Test(arguments: mechanisms) func threadSafeSetInsertAndContains(mechanism: ThreadSafeMechanism) throws {
    let set = ThreadSafe<Set<Int>>(mechanism: mechanism)
    set.insert(1)
    set.insert(2)
    #expect(set.count == 2)
    #expect(set.contains(1))
    #expect(set.contains(3) == false)
}

@Test(arguments: mechanisms) func threadSafeSetInitWithSequence(mechanism: ThreadSafeMechanism) throws {
    let set = ThreadSafe(Set([1, 2, 3]), mechanism: mechanism)
    #expect(set.wrappedValue == [1, 2, 3])
}

@Test(arguments: mechanisms) func threadSafeSetIsEmpty(mechanism: ThreadSafeMechanism) throws {
    let empty = ThreadSafe<Set<Int>>(mechanism: mechanism)
    #expect(empty.isEmpty)

    let set = ThreadSafe(Set([1]), mechanism: mechanism)
    #expect(set.isEmpty == false)
}

@Test(arguments: mechanisms) func threadSafeSetInsertReturnsInsertedAndMember(mechanism: ThreadSafeMechanism) throws {
    let set = ThreadSafe(Set([1]), mechanism: mechanism)
    let first = set.insert(1)
    #expect(first.inserted == false)
    #expect(first.memberAfterInsert == 1)

    let second = set.insert(2)
    #expect(second.inserted)
    #expect(second.memberAfterInsert == 2)
}

@Test(arguments: mechanisms) func threadSafeSetRemove(mechanism: ThreadSafeMechanism) throws {
    let set = ThreadSafe(Set([1, 2, 3]), mechanism: mechanism)
    let removed = set.remove(2)
    #expect(removed == 2)
    #expect(set.wrappedValue == [1, 3])
    #expect(set.remove(2) == nil)
}

@Test(arguments: mechanisms) func threadSafeSetRemoveAll(mechanism: ThreadSafeMechanism) throws {
    let set = ThreadSafe(Set([1, 2, 3]), mechanism: mechanism)
    set.removeAll()
    #expect(set.isEmpty)
}

@Test(arguments: mechanisms) func threadSafeSetUpdateWith(mechanism: ThreadSafeMechanism) throws {
    let set = ThreadSafe(Set([1, 2]), mechanism: mechanism)
    #expect(set.update(with: 1) == 1)
    #expect(set.update(with: 3) == nil)
    #expect(set.wrappedValue == [1, 2, 3])
}

@Test(arguments: mechanisms) func threadSafeSetUnionIntersectionSymmetricDifference(mechanism: ThreadSafeMechanism) throws {
    let set = ThreadSafe(Set([1, 2, 3]), mechanism: mechanism)
    #expect(set.union([3, 4]) == [1, 2, 3, 4])
    #expect(set.intersection([2, 3, 4]) == [2, 3])
    #expect(set.symmetricDifference([2, 3, 4]) == [1, 4])
    #expect(set.wrappedValue == [1, 2, 3])
}

@Test(arguments: mechanisms) func threadSafeSetFormUnion(mechanism: ThreadSafeMechanism) throws {
    let set = ThreadSafe(Set([1, 2]), mechanism: mechanism)
    set.formUnion([2, 3])
    #expect(set.wrappedValue == [1, 2, 3])
}

@Test(arguments: mechanisms) func threadSafeSetFormIntersection(mechanism: ThreadSafeMechanism) throws {
    let set = ThreadSafe(Set([1, 2, 3]), mechanism: mechanism)
    set.formIntersection([2, 3, 4])
    #expect(set.wrappedValue == [2, 3])
}

@Test(arguments: mechanisms) func threadSafeSetSubtract(mechanism: ThreadSafeMechanism) throws {
    let set = ThreadSafe(Set([1, 2, 3]), mechanism: mechanism)
    set.subtract([2])
    #expect(set.wrappedValue == [1, 3])
}

@Test(arguments: mechanisms) func threadSafeSetFormSymmetricDifference(mechanism: ThreadSafeMechanism) throws {
    let set = ThreadSafe(Set([1, 2, 3]), mechanism: mechanism)
    set.formSymmetricDifference([2, 3, 4])
    #expect(set.wrappedValue == [1, 4])
}

@Test(arguments: mechanisms) func threadSafeSetSubsetSupersetDisjoint(mechanism: ThreadSafeMechanism) throws {
    let set = ThreadSafe(Set([1, 2]), mechanism: mechanism)
    #expect(set.isSubset(of: [1, 2, 3]))
    #expect(set.isSuperset(of: [1]))
    #expect(set.isDisjoint(with: [3, 4]))
    #expect(set.isStrictSubset(of: [1, 2, 3]))
    #expect(set.isStrictSubset(of: [1, 2]) == false)
    #expect(set.isStrictSuperset(of: [1]))
    #expect(set.isStrictSuperset(of: [1, 2]) == false)
}

@Test(arguments: mechanisms) func threadSafeSetForEach(mechanism: ThreadSafeMechanism) throws {
    let set = ThreadSafe(Set([1, 2, 3]), mechanism: mechanism)
    let sum = ThreadSafe(wrappedValue: 0)
    set.forEach { element in sum.mutate { $0 += element } }
    #expect(sum.wrappedValue == 6)
}

@Test(arguments: mechanisms) func threadSafeSetMap(mechanism: ThreadSafeMechanism) throws {
    let set = ThreadSafe(Set([1, 2, 3]), mechanism: mechanism)
    let doubled = set.map { $0 * 2 }
    #expect(Set(doubled) == [2, 4, 6])
}

@Test(arguments: mechanisms) func threadSafeSetConcurrentInsertsDoNotDropWrites(mechanism: ThreadSafeMechanism) throws {
    let set = ThreadSafe<Set<Int>>(mechanism: mechanism)
    DispatchQueue.concurrentPerform(iterations: concurrencyIterations) { i in
        set.insert(i)
    }
    #expect(set.count == concurrencyIterations)
}

// Interleaves reads with writes to exercise the backing mechanism specifically: whether it's the
// unfair lock (all access exclusive) or the concurrent queue + barrier (concurrent readers, exclusive
// writers), concurrent readers and writers still can't race. A real race here is caught by Thread
// Sanitizer (`swift test --sanitize=thread`), not just by a dropped-write count.
@Test(arguments: mechanisms) func threadSafeSetConcurrentReadsDuringWritesDoNotRace(mechanism: ThreadSafeMechanism) throws {
    let set = ThreadSafe<Set<Int>>(mechanism: mechanism)
    DispatchQueue.concurrentPerform(iterations: concurrencyIterations * 2) { i in
        if i % 2 == 0 {
            set.insert(i)
        } else {
            _ = set.count
            _ = set.wrappedValue
            _ = set.contains(0)
        }
    }
    #expect(set.count == concurrencyIterations)
}

@Test(arguments: mechanisms) func threadSafeSetMutateReturnsValueAndMutates(mechanism: ThreadSafeMechanism) throws {
    let set = ThreadSafe(Set([1, 2, 3]), mechanism: mechanism)
    let sum = set.mutate { members -> Int in
        let total = members.reduce(0, +)
        members.insert(total)
        return total
    }
    #expect(sum == 6)
    #expect(set.wrappedValue == [1, 2, 3, 6])
}

@Test(arguments: mechanisms) func threadSafeSetCodableRoundTrip(mechanism: ThreadSafeMechanism) throws {
    let set = ThreadSafe(Set([1, 2, 3]), mechanism: mechanism)
    let data = try JSONEncoder().encode(set)
    let decoded = try JSONDecoder().decode(ThreadSafe<Set<Int>>.self, from: data)
    #expect(decoded.wrappedValue == [1, 2, 3])
}

// Auto-synthesized Codable on a containing type only compiles because
// ThreadSafe<Set<Int>> conforms to Codable; this is the whole point of the feature.
@Test func threadSafeSetCodableRoundTripInsideContainingType() throws {
    struct Container: Codable {
        let members: ThreadSafe<Set<Int>>
    }
    let container = Container(members: ThreadSafe(Set([1, 2])))
    let data = try JSONEncoder().encode(container)
    let decoded = try JSONDecoder().decode(Container.self, from: data)
    #expect(decoded.members.wrappedValue == [1, 2])
}

@Test func threadSafeSetEquatableComparesMembers() throws {
    #expect(ThreadSafe(Set([1, 2, 3])) == ThreadSafe(Set([1, 2, 3])))
    #expect(ThreadSafe(Set([1, 2, 3])) != ThreadSafe(Set([1, 2])))
}

// Auto-synthesized Equatable on a containing type only compiles because
// ThreadSafe<Set<Int>> conforms to Equatable; this is the whole point of the feature.
@Test func threadSafeSetEquatableInsideContainingType() throws {
    struct Container: Equatable {
        let members: ThreadSafe<Set<Int>>
    }
    #expect(Container(members: ThreadSafe(Set([1, 2]))) == Container(members: ThreadSafe(Set([1, 2]))))
    #expect(Container(members: ThreadSafe(Set([1, 2]))) != Container(members: ThreadSafe(Set([1, 3]))))
}

@Test(arguments: mechanisms) func threadSafeSetDescriptionContainsMembers(mechanism: ThreadSafeMechanism) throws {
    let set = ThreadSafe(Set([1]), mechanism: mechanism)
    #expect(set.description == "ThreadSafe([1])")
}

@Test(arguments: mechanisms) func threadSafeSetPropertyWrapperReadsSnapshotAndProjectsInstance(mechanism: ThreadSafeMechanism) throws {
    @ThreadSafe(mechanism: mechanism) var members: Set<Int> = [1, 2, 3]
    #expect(members == [1, 2, 3])
    $members.insert(4)
    #expect(members == [1, 2, 3, 4])
    #expect($members.count == 4)
}
