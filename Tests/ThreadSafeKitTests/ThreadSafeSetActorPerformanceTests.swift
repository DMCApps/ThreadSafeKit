import Testing

@testable import ThreadSafeKit

// Performance coverage for `ThreadSafeSet`: every public member stays within a generous
// absolute-time ceiling for an actor hop (see `assertFast`'s async overload in TestSupport.swift).

@Test
func setActorReadsAreFast() async {
    let set = ThreadSafeSet([1, 2, 3])
    await assertFast("count") { _ = await set.count }
    await assertFast("isEmpty") { _ = await set.isEmpty }
    await assertFast("elements") { _ = await set.elements }
    await assertFast("contains") { _ = await set.contains(1) }
    await assertFast("forEach") { await set.forEach { _ = $0 } }
    await assertFast("map") { _ = await set.map { $0 } }
    await assertFast("union") { _ = await set.union([4]) }
    await assertFast("intersection") { _ = await set.intersection([1]) }
    await assertFast("symmetricDifference") { _ = await set.symmetricDifference([4]) }
    await assertFast("isSubset(of:)") { _ = await set.isSubset(of: [1, 2, 3, 4]) }
    await assertFast("isSuperset(of:)") { _ = await set.isSuperset(of: [1]) }
    await assertFast("isDisjoint(with:)") { _ = await set.isDisjoint(with: [4]) }
    await assertFast("isStrictSubset(of:)") { _ = await set.isStrictSubset(of: [1, 2, 3, 4]) }
    await assertFast("isStrictSuperset(of:)") { _ = await set.isStrictSuperset(of: [1]) }
}

@Test
func setActorWritesAreFast() async {
    let set = ThreadSafeSet([1, 2, 3])
    await assertFast("insert") { await set.insert(0) }
    await assertFast("remove") { _ = await set.remove(0) }
    await assertFast("update(with:)") { _ = await set.update(with: 1) }
    await assertFast("formUnion") { await set.formUnion([1]) }
    await assertFast("formIntersection") { await set.formIntersection([1, 2, 3]) }
    await assertFast("subtract") { await set.subtract([]) }
    await assertFast("formSymmetricDifference") { await set.formSymmetricDifference([]) }
    await assertFast("mutate") { await set.mutate { $0.insert(0); $0.remove(0) } }
}

@Test
func setActorRemoveAllIsFast() async {
    let set = ThreadSafeSet([1, 2, 3])
    await assertFast("removeAll") { await set.removeAll() }
}
