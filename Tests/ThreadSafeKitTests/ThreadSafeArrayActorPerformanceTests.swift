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
    await assertFast("append(contentsOf:)") { await array.append(contentsOf: [0]) }
    await assertFast("insert(_:at:)") { await array.insert(0, at: 0) }
    await assertFast("popLast") { _ = await array.popLast() }
    await assertFast("setElement(_:at:)") { await array.setElement(0, at: 0) }
    await assertFast("removeFirst") { await array.append(0); _ = await array.removeFirst() }
    await assertFast("removeLast") { await array.append(0); _ = await array.removeLast() }
    await assertFast("reserveCapacity") { await array.reserveCapacity(10) }
    // reverse/sort/shuffle go through generic MutableCollection & RandomAccessCollection dispatch
    // (vs. append/pop's directly-specialized calls) and shuffle additionally draws from the system
    // RNG, so all three carry real per-call overhead beyond the 300us ceiling tuned for simple actor
    // hops — ceilings widened further to also clear `--sanitize=thread`'s per-call instrumentation cost.
    await assertFast("reverse", maxMicroseconds: 1_500) { await array.reverse() }
    await assertFast("sort", maxMicroseconds: 3_000) { await array.sort() }
    await assertFast("sort(by:)", maxMicroseconds: 3_000) { await array.sort(by: <) }
    await assertFast("shuffle", maxMicroseconds: 10_000) { await array.shuffle() }
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

@Test
func arrayActorReadOnlyDerivedCollectionsAreFast() async {
    let array = ThreadSafeArray([1, 2, 3])
    await assertFast("contains") { _ = await array.contains(2) }
    await assertFast("firstIndex(where:)") { _ = await array.firstIndex(where: { $0 == 2 }) }
    await assertFast("firstIndex(of:)") { _ = await array.firstIndex(of: 2) }
    await assertFast("filter") { _ = await array.filter { $0 > 1 } }
    await assertFast("compactMap") { _ = await array.compactMap { $0 } }
    await assertFast("sorted") { _ = await array.sorted() }
    await assertFast("sorted(by:)") { _ = await array.sorted(by: <) }
    await assertFast("min/max") { _ = await array.min(); _ = await array.max() }
    await assertFast("allSatisfy") { _ = await array.allSatisfy { $0 > 0 } }
    await assertFast("prefix/suffix") { _ = await array.prefix(1); _ = await array.suffix(1) }
}
