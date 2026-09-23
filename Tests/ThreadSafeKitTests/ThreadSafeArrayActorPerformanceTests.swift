import Testing

@testable import ThreadSafeKit

// Performance coverage for `ThreadSafeArray`: every public member stays within a generous
// absolute-time ceiling for an actor hop (see `assertFast`'s async overload in TestSupport.swift).

@Test
func arrayActorReadsAreFast() async {
    let array = ThreadSafeArray([1, 2, 3])
    await assertFast("count") { _ = await array.count }
    await assertFast("isEmpty") { _ = await array.isEmpty }
    await assertFast("first") { _ = await array.first }
    await assertFast("last") { _ = await array.last }
    await assertFast("elements") { _ = await array.elements }
    await assertFast("subscript(index:) get") { _ = await array[0] }
    await assertFast("subscript(safe:)") { _ = await array[safe: 0] }
    await assertFast("forEach") { await array.forEach { _ = $0 } }
    await assertFast("map") { _ = await array.map { $0 } }
}

@Test
func arrayActorWritesAreFast() async {
    let array = ThreadSafeArray([1, 2, 3])
    await assertFast("append") { await array.append(0) }
    await assertFast("push") { await array.push(0) }
    await assertFast("pop") { _ = await array.pop() }
    await assertFast("setElement(_:at:)") { await array.setElement(0, at: 0) }
    await assertFast("mutate") { await array.mutate { $0.append(0); $0.removeLast() } }
}

@Test
func arrayActorRemoveAtIsFast() async {
    let sampleSize = 500
    let array = ThreadSafeArray(Array(0..<sampleSize))
    await assertFast("remove(at:)", sampleSize: sampleSize) { _ = await array.remove(at: 0) }
}

@Test
func arrayActorRemoveAllIsFast() async {
    let array = ThreadSafeArray([1, 2, 3])
    await assertFast("removeAll") { await array.removeAll() }
}
