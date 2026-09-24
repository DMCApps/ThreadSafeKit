import Foundation
import Testing
@testable import ThreadSafeKit

private let mechanisms: [ThreadSafeMechanism] = [.lock, .readerWriterLock]

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

@Test(arguments: mechanisms) func threadSafeSetElements(mechanism: ThreadSafeMechanism) throws {
    let set = ThreadSafe(Set([1, 2, 3]), mechanism: mechanism)
    #expect(set.elements == [1, 2, 3])
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

@Test(arguments: mechanisms) func threadSafeSetSubtracting(mechanism: ThreadSafeMechanism) throws {
    let set = ThreadSafe(Set([1, 2, 3]), mechanism: mechanism)
    #expect(set.subtracting([2, 3]) == [1])
    #expect(set.wrappedValue == [1, 2, 3])
}

@Test(arguments: mechanisms) func threadSafeSetPopFirst(mechanism: ThreadSafeMechanism) throws {
    let set = ThreadSafe(Set([1]), mechanism: mechanism)
    #expect(set.popFirst() == 1)
    #expect(set.isEmpty)

    let empty = ThreadSafe<Set<Int>>(mechanism: mechanism)
    #expect(empty.popFirst() == nil)
}

// Concurrent drains must remove every element exactly once — no duplicates, no drops.
@Test(arguments: mechanisms) func threadSafeSetConcurrentPopFirstDrainsExactlyOnce(mechanism: ThreadSafeMechanism) throws {
    let n = 2_000
    let set = ThreadSafe(Set(0..<n), mechanism: mechanism)
    let popped = ThreadSafe<[Int]>(mechanism: .lock)
    DispatchQueue.concurrentPerform(iterations: 8) { _ in
        while let value = set.popFirst() {
            popped.append(value)
        }
    }
    #expect(set.isEmpty)
    #expect(popped.elements.count == n)
    #expect(Set(popped.elements) == Set(0..<n))
}

@Test(arguments: mechanisms) func threadSafeSetRemoveFirst(mechanism: ThreadSafeMechanism) throws {
    let set = ThreadSafe(Set([1]), mechanism: mechanism)
    #expect(set.removeFirst() == 1)
    #expect(set.isEmpty)
}

// `removeFirst()` traps on an empty set (unlike `popFirst()`), so this drains safely by calling
// it exactly once per seeded element — one `concurrentPerform` iteration per element, rather than
// looping each worker to empty — instead of a racy isEmpty-then-removeFirst check-then-act.
// Concurrent calls must still remove every element exactly once, no duplicates, no drops.
@Test(arguments: mechanisms) func threadSafeSetConcurrentRemoveFirstDrainsExactlyOnce(mechanism: ThreadSafeMechanism) throws {
    let n = 2_000
    let set = ThreadSafe(Set(0..<n), mechanism: mechanism)
    let removed = ThreadSafe<[Int]>(mechanism: .lock)
    DispatchQueue.concurrentPerform(iterations: n) { _ in
        removed.append(set.removeFirst())
    }
    #expect(set.isEmpty)
    #expect(removed.elements.count == n)
    #expect(Set(removed.elements) == Set(0..<n))
}

@Test(arguments: mechanisms) func threadSafeSetReserveCapacity(mechanism: ThreadSafeMechanism) throws {
    let set = ThreadSafe(Set([1, 2, 3]), mechanism: mechanism)
    set.reserveCapacity(100)
    #expect(set.wrappedValue == [1, 2, 3])
}

// Concurrent `reserveCapacity` calls interleaved with concurrent inserts must not corrupt or
// drop any insert — `reserveCapacity` only affects unobservable storage capacity.
@Test(arguments: mechanisms) func threadSafeSetConcurrentReserveCapacityDoesNotCorruptConcurrentInserts(mechanism: ThreadSafeMechanism) throws {
    let set = ThreadSafe<Set<Int>>(mechanism: mechanism)
    let n = concurrencyIterations
    DispatchQueue.concurrentPerform(iterations: n * 2) { i in
        if i < n {
            set.insert(i)
        } else {
            set.reserveCapacity(1_000)
        }
    }
    #expect(set.count == n)
    #expect(set.wrappedValue == Set(0..<n))
}

@Test(arguments: mechanisms) func threadSafeSetRemoveAllKeepingCapacity(mechanism: ThreadSafeMechanism) throws {
    let set = ThreadSafe(Set([1, 2, 3]), mechanism: mechanism)
    set.removeAll(keepingCapacity: true)
    #expect(set.isEmpty)
}

// Every `removeAll(keepingCapacity:)` call unconditionally empties the set, so whichever call is
// the LAST one in the actual (lock-enforced) execution order leaves the set empty at that instant;
// only inserts after that point can leave anything behind, and inserted values are always >= n —
// so no original seed value can ever survive, deterministically, regardless of interleaving.
@Test(arguments: mechanisms) func threadSafeSetRemoveAllKeepingCapacityConcurrentWithInsertsNeverLeavesSeedValues(mechanism: ThreadSafeMechanism) throws {
    let n = 600
    let k = 4
    let set = ThreadSafe(Set(0..<n), mechanism: mechanism)
    DispatchQueue.concurrentPerform(iterations: k * 2) { i in
        if i < k {
            for _ in 0..<100 { set.removeAll(keepingCapacity: true) }
        } else {
            for j in 0..<100 { set.insert(n + (i - k) * 100 + j) }
        }
    }
    let remaining = set.wrappedValue
    #expect(remaining.isDisjoint(with: Set(0..<n)))
    #expect(remaining.isSubset(of: Set(n..<(n + k * 100))))
}

@Test(arguments: mechanisms) func threadSafeSetFilterReturnsSet(mechanism: ThreadSafeMechanism) throws {
    let set = ThreadSafe(Set([1, 2, 3, 4]), mechanism: mechanism)
    let evens: Set<Int> = set.filter { $0 % 2 == 0 }
    #expect(evens == [2, 4])
}

@Test(arguments: mechanisms) func threadSafeSetFirstWhere(mechanism: ThreadSafeMechanism) throws {
    let set = ThreadSafe(Set([1, 2, 3]), mechanism: mechanism)
    #expect(set.first(where: { $0 == 2 }) == 2)
    #expect(set.first(where: { $0 == 4 }) == nil)
}

@Test(arguments: mechanisms) func threadSafeSetContainsWhere(mechanism: ThreadSafeMechanism) throws {
    let set = ThreadSafe(Set([1, 2, 3]), mechanism: mechanism)
    #expect(set.contains(where: { $0 == 2 }) == true)
    #expect(set.contains(where: { $0 == 4 }) == false)
}

@Test(arguments: mechanisms) func threadSafeSetCountWhere(mechanism: ThreadSafeMechanism) throws {
    let set = ThreadSafe(Set([1, 2, 3, 4]), mechanism: mechanism)
    #expect(set.count(where: { $0 % 2 == 0 }) == 2)
}

@Test(arguments: mechanisms) func threadSafeSetMinByAndMaxBy(mechanism: ThreadSafeMechanism) throws {
    let set = ThreadSafe(Set([3, 1, 2]), mechanism: mechanism)
    #expect(set.min(by: <) == 1)
    #expect(set.max(by: <) == 3)
}

@Test(arguments: mechanisms) func threadSafeSetReduceNonInto(mechanism: ThreadSafeMechanism) throws {
    let set = ThreadSafe(Set([1, 2, 3, 4]), mechanism: mechanism)
    let sum = set.reduce(0, +)
    #expect(sum == 10)
}

@Test(arguments: mechanisms) func threadSafeSetRandomElement(mechanism: ThreadSafeMechanism) throws {
    let set = ThreadSafe(Set([1, 2, 3]), mechanism: mechanism)
    #expect([1, 2, 3].contains(set.randomElement()!))

    let empty = ThreadSafe<Set<Int>>(mechanism: mechanism)
    #expect(empty.randomElement() == nil)
}

@Test(arguments: mechanisms) func threadSafeSetAllSatisfy(mechanism: ThreadSafeMechanism) throws {
    let set = ThreadSafe(Set([2, 4, 6]), mechanism: mechanism)
    #expect(set.allSatisfy { $0 % 2 == 0 })
    #expect(set.allSatisfy { $0 > 2 } == false)
}

@Test(arguments: mechanisms) func threadSafeSetCompactMap(mechanism: ThreadSafeMechanism) throws {
    let set = ThreadSafe(Set([1, 2, 3, 4]), mechanism: mechanism)
    #expect(Set(set.compactMap { $0 % 2 == 0 ? $0 : nil }) == [2, 4])
}

@Test(arguments: mechanisms) func threadSafeSetSortedBy(mechanism: ThreadSafeMechanism) throws {
    let set = ThreadSafe(Set([3, 1, 2]), mechanism: mechanism)
    #expect(set.sorted(by: >) == [3, 2, 1])
}

@Test(arguments: mechanisms) func threadSafeSetSortedMinMax(mechanism: ThreadSafeMechanism) throws {
    let set = ThreadSafe(Set([3, 1, 2]), mechanism: mechanism)
    #expect(set.sorted() == [1, 2, 3])
    #expect(set.min() == 1)
    #expect(set.max() == 3)
}
