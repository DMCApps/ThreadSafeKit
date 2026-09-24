import Foundation
import Testing

@testable import ThreadSafeKit

// Performance coverage for the core `ThreadSafe<Value>` wrapper (both `.lock` and
// `.readerWriterLock` mechanisms): every representative read/write member stays within a
// generous absolute-time ceiling, plus regression tests for the specific O(n)-per-write
// defect this file was created to guard against.

private let mechanisms: [ThreadSafeMechanism] = [.lock, .readerWriterLock]

// MARK: - Array shape

@Test(.tags(.performance), arguments: mechanisms)
func arrayShapeReadsAreFast(mechanism: ThreadSafeMechanism) {
    let array = ThreadSafe([1, 2, 3], mechanism: mechanism)
    assertFast("count") { _ = array.count }
    assertFast("isEmpty") { _ = array.isEmpty }
    assertFast("first/last") { _ = array.first; _ = array.last }
    assertFast("elements") { _ = array.elements }
    assertFast("subscript(safe:)") { _ = array[safe: 0] }
    assertFast("forEach") { array.forEach { _ = $0 } }
    assertFast("map") { _ = array.map { $0 } }
    assertFast("reduce(into:)") { _ = array.reduce(into: 0) { $0 += $1 } }
    assertFast("description") { _ = array.description }
    assertFast("==") { _ = (array.elements == array.elements) }
}

@Test(.tags(.performance), arguments: mechanisms)
func arrayShapeWritesAreFast(mechanism: ThreadSafeMechanism) {
    let array = ThreadSafe([1, 2, 3], mechanism: mechanism)
    assertFast("append") { array.append(0) }
    assertFast("append(contentsOf:)") { array.append(contentsOf: [0]) }
    assertFast("insert(_:at:)") { array.insert(0, at: 0) }
    assertFast("popLast") { _ = array.popLast() }
    assertFast("subscript(index:) set") { array[0] = 0 }
    assertFast("removeFirst") { array.append(0); _ = array.removeFirst() }
    assertFast("removeLast") { array.append(0); _ = array.removeLast() }
    assertFast("reserveCapacity") { array.reserveCapacity(10) }
    // reverse/sort/shuffle go through generic MutableCollection & RandomAccessCollection dispatch
    // (vs. append/pop's directly-specialized calls) and shuffle additionally draws from the system
    // RNG, so all three carry real per-call overhead beyond the 50us ceiling tuned for simple ops —
    // ceilings widened further to also clear `--sanitize=thread`'s per-call instrumentation cost.
    assertFast("reverse", maxMicroseconds: 1_500) { array.reverse() }
    assertFast("sort", maxMicroseconds: 3_000) { array.sort() }
    assertFast("sort(by:)", maxMicroseconds: 3_000) { array.sort(by: <) }
    assertFast("shuffle", maxMicroseconds: 20_000) { array.shuffle() }
    assertFast("insert(at:)") { array.insert(0, at: 0); _ = array.removeFirst() }
    assertFast("mutate") { array.mutate { $0.append(0); $0.removeLast() } }
}

@Test(.tags(.performance), arguments: mechanisms)
func arrayShapeReadOnlyDerivedCollectionsAreFast(mechanism: ThreadSafeMechanism) {
    let array = ThreadSafe([1, 2, 3], mechanism: mechanism)
    assertFast("contains") { _ = array.contains(2) }
    assertFast("firstIndex(where:)") { _ = array.firstIndex(where: { $0 == 2 }) }
    assertFast("firstIndex(of:)") { _ = array.firstIndex(of: 2) }
    assertFast("filter") { _ = array.filter { $0 > 1 } }
    assertFast("compactMap") { _ = array.compactMap { $0 } }
    assertFast("sorted") { _ = array.sorted() }
    assertFast("sorted(by:)") { _ = array.sorted(by: <) }
    assertFast("min/max") { _ = array.min(); _ = array.max() }
    assertFast("allSatisfy") { _ = array.allSatisfy { $0 > 0 } }
    assertFast("prefix/suffix") { _ = array.prefix(1); _ = array.suffix(1) }
}

// MARK: - Dictionary shape

@Test(.tags(.performance), arguments: mechanisms)
func dictionaryShapeReadsAreFast(mechanism: ThreadSafeMechanism) {
    let dictionary = ThreadSafe(["a": 1, "b": 2], mechanism: mechanism)
    assertFast("count") { _ = dictionary.count }
    assertFast("isEmpty") { _ = dictionary.isEmpty }
    assertFast("dictionary") { _ = dictionary.dictionary }
    assertFast("subscript(key:) get") { _ = dictionary["a"] }
    assertFast("keys") { _ = dictionary.keys }
    assertFast("values") { _ = dictionary.values }
    assertFast("mapValues") { _ = dictionary.mapValues { $0 } }
    assertFast("compactMapValues") { _ = dictionary.compactMapValues { $0 } }
    assertFast("filter") { _ = dictionary.filter { $0.value > 0 } }
    assertFast("contains(where:)") { _ = dictionary.contains { $0.value > 0 } }
}

@Test(.tags(.performance), arguments: mechanisms)
func dictionaryShapeWritesAreFast(mechanism: ThreadSafeMechanism) {
    let dictionary = ThreadSafe(["a": 1, "b": 2], mechanism: mechanism)
    assertFast("subscript(key:) set") { dictionary["z"] = 1 }
    assertFast("removeValue(forKey:)") { _ = dictionary.removeValue(forKey: "does-not-exist") }
    assertFast("updateValue(_:forKey:)") { _ = dictionary.updateValue(1, forKey: "z") }
    assertFast("merge") { dictionary.merge(["y": 1]) { old, _ in old } }
    assertFast("mutate") { dictionary.mutate { $0["z"] = 1 } }
}

// MARK: - Set shape

@Test(.tags(.performance), arguments: mechanisms)
func setShapeReadsAreFast(mechanism: ThreadSafeMechanism) {
    let set = ThreadSafe(Set([1, 2, 3]), mechanism: mechanism)
    assertFast("count") { _ = set.count }
    assertFast("isEmpty") { _ = set.isEmpty }
    assertFast("wrappedValue") { _ = set.wrappedValue }
    assertFast("contains") { _ = set.contains(1) }
    assertFast("description") { _ = set.description }
    assertFast("union") { _ = set.union([4]) }
    assertFast("intersection") { _ = set.intersection([1]) }
    assertFast("symmetricDifference") { _ = set.symmetricDifference([4]) }
    assertFast("isSubset(of:)") { _ = set.isSubset(of: [1, 2, 3, 4]) }
    assertFast("isSuperset(of:)") { _ = set.isSuperset(of: [1]) }
    assertFast("isDisjoint(with:)") { _ = set.isDisjoint(with: [4]) }
    assertFast("isStrictSubset(of:)") { _ = set.isStrictSubset(of: [1, 2, 3, 4]) }
    assertFast("isStrictSuperset(of:)") { _ = set.isStrictSuperset(of: [1]) }
}

@Test(.tags(.performance), arguments: mechanisms)
func setShapeWritesAreFast(mechanism: ThreadSafeMechanism) {
    let set = ThreadSafe(Set([1, 2, 3]), mechanism: mechanism)
    assertFast("insert") { set.insert(0) }
    assertFast("remove") { _ = set.remove(0) }
    assertFast("update(with:)") { _ = set.update(with: 1) }
    assertFast("formUnion") { set.formUnion([1]) }
    assertFast("formIntersection") { set.formIntersection([1, 2, 3]) }
    assertFast("subtract") { set.subtract([]) }
    assertFast("formSymmetricDifference") { set.formSymmetricDifference([]) }
    assertFast("mutate") { set.mutate { $0.insert(0); $0.remove(0) } }
}

// MARK: - Atomic/scalar shape

@Test(.tags(.performance), arguments: mechanisms)
func atomicShapeReadsAndWritesAreFast(mechanism: ThreadSafeMechanism) {
    let value = ThreadSafe(0, mechanism: mechanism)
    assertFast("wrappedValue get") { _ = value.wrappedValue }
    assertFast("mutate") { value.mutate { $0 += 1 } }
}

// MARK: - Regression: per-write cost must not scale with collection size

// `write` used to keep `storage` (a second reference to the CoW buffer) alive across the whole
// mutation, so every single write defeated copy-on-write and copied the entire collection — an
// O(n) write, i.e. O(n^2) to build an n-element collection. This was fixed by making `value`
// uniquely referenced during the call. These tests guard the fix by asserting per-write cost at a
// large preload isn't dramatically worse than at a small one — a regression back to the
// O(n) shape blows past `maxSlowdown` by ~100x; the fix stays under ~5x in practice.
// Bounded by ratio (not absolute time) to stay meaningful across machines/CI load.

private let smallPreload = 1_000
private let largePreload = 200_000
private let writesPerSample = 500
private let maxSlowdown = 20.0

@Test(.tags(.performance), arguments: mechanisms)
func arrayAppendCostDoesNotScaleWithCollectionSize(mechanism: ThreadSafeMechanism) {
    let small = ThreadSafe(Array(0..<smallPreload), mechanism: mechanism)
    let smallNsPerOp = averageNanoseconds(over: writesPerSample) { small.append(0) }

    let large = ThreadSafe(Array(0..<largePreload), mechanism: mechanism)
    let largeNsPerOp = averageNanoseconds(over: writesPerSample) { large.append(0) }

    #expect(
        largeNsPerOp < smallNsPerOp * maxSlowdown,
        "append at \(largePreload) elements (\(largeNsPerOp) ns/op) is more than \(maxSlowdown)x the cost at \(smallPreload) elements (\(smallNsPerOp) ns/op) — per-write cost is scaling with collection size again"
    )
}

@Test(.tags(.performance), arguments: mechanisms)
func dictionarySubscriptSetCostDoesNotScaleWithCollectionSize(mechanism: ThreadSafeMechanism) {
    let small = ThreadSafe(Dictionary(uniqueKeysWithValues: (0..<smallPreload).map { ($0, $0) }), mechanism: mechanism)
    let smallNsPerOp = averageNanoseconds(over: writesPerSample) { small[-1] = 0 }

    let large = ThreadSafe(Dictionary(uniqueKeysWithValues: (0..<largePreload).map { ($0, $0) }), mechanism: mechanism)
    let largeNsPerOp = averageNanoseconds(over: writesPerSample) { large[-1] = 0 }

    #expect(
        largeNsPerOp < smallNsPerOp * maxSlowdown,
        "subscript set at \(largePreload) entries (\(largeNsPerOp) ns/op) is more than \(maxSlowdown)x the cost at \(smallPreload) entries (\(smallNsPerOp) ns/op) — per-write cost is scaling with collection size again"
    )
}
