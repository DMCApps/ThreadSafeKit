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
}

@Test
func setActorWritesAreFast() async {
    let set = ThreadSafeSet([1, 2, 3])
    await assertFast("insert") { await set.insert(0) }
    await assertFast("remove") { _ = await set.remove(0) }
    await assertFast("mutate") { await set.mutate { $0.insert(0); $0.remove(0) } }
}

@Test
func setActorRemoveAllIsFast() async {
    let set = ThreadSafeSet([1, 2, 3])
    await assertFast("removeAll") { await set.removeAll() }
}
