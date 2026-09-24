import Foundation
import Testing

@testable import ThreadSafeKit

// Performance coverage for the core `ThreadSafe<Value>` wrapper (both `.lock` and
// `.dispatchQueue` mechanisms): every representative read/write member stays within a
// generous absolute-time ceiling, plus regression tests for the specific O(n)-per-write
// defect this file was created to guard against.

private let mechanisms: [ThreadSafeMechanism] = [.lock, .dispatchQueue]

// MARK: - Array shape

@Test(arguments: mechanisms)
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

@Test(arguments: mechanisms)
func arrayShapeWritesAreFast(mechanism: ThreadSafeMechanism) {
    let array = ThreadSafe([1, 2, 3], mechanism: mechanism)
    assertFast("append") { array.append(0) }
    assertFast("push") { array.push(0) }
    assertFast("pop") { _ = array.pop() }
    assertFast("subscript(index:) set") { array[0] = 0 }
    assertFast("mutate") { array.mutate { $0.append(0); $0.removeLast() } }
}

// MARK: - Dictionary shape

@Test(arguments: mechanisms)
func dictionaryShapeReadsAreFast(mechanism: ThreadSafeMechanism) {
    let dictionary = ThreadSafe(["a": 1, "b": 2], mechanism: mechanism)
    assertFast("count") { _ = dictionary.count }
    assertFast("isEmpty") { _ = dictionary.isEmpty }
    assertFast("dictionary") { _ = dictionary.dictionary }
    assertFast("getValue(forKey:)") { _ = dictionary.getValue(forKey: "a") }
    assertFast("subscript(key:) get") { _ = dictionary["a"] }
}

@Test(arguments: mechanisms)
func dictionaryShapeWritesAreFast(mechanism: ThreadSafeMechanism) {
    let dictionary = ThreadSafe(["a": 1, "b": 2], mechanism: mechanism)
    assertFast("setValue(_:forKey:)") { dictionary.setValue(1, forKey: "z") }
    assertFast("subscript(key:) set") { dictionary["z"] = 1 }
    assertFast("removeValue(forKey:)") { _ = dictionary.removeValue(forKey: "does-not-exist") }
    assertFast("merge") { dictionary.merge(["y": 1]) { old, _ in old } }
    assertFast("mutate") { dictionary.mutate { $0["z"] = 1 } }
}

// MARK: - Set shape

@Test(arguments: mechanisms)
func setShapeReadsAreFast(mechanism: ThreadSafeMechanism) {
    let set = ThreadSafe(Set([1, 2, 3]), mechanism: mechanism)
    assertFast("count") { _ = set.count }
    assertFast("isEmpty") { _ = set.isEmpty }
    assertFast("wrappedValue") { _ = set.wrappedValue }
    assertFast("contains") { _ = set.contains(1) }
    assertFast("description") { _ = set.description }
}

@Test(arguments: mechanisms)
func setShapeWritesAreFast(mechanism: ThreadSafeMechanism) {
    let set = ThreadSafe(Set([1, 2, 3]), mechanism: mechanism)
    assertFast("insert") { set.insert(0) }
    assertFast("remove") { _ = set.remove(0) }
    assertFast("mutate") { set.mutate { $0.insert(0); $0.remove(0) } }
}

// MARK: - Atomic/scalar shape

@Test(arguments: mechanisms)
func atomicShapeReadsAndWritesAreFast(mechanism: ThreadSafeMechanism) {
    let value = ThreadSafe(0, mechanism: mechanism)
    assertFast("wrappedValue get") { _ = value.wrappedValue }
    assertFast("mutate") { value.mutate { $0 += 1 } }
}

// MARK: - Regression: per-write cost must not scale with collection size

// `write`'s `.queue` case used to keep `storage` (a second reference to the CoW buffer)
// alive across the whole mutation, so every single write defeated copy-on-write and copied
// the entire collection — an O(n) write, i.e. O(n^2) to build an n-element collection.
// `storage = nil` before mutating (ThreadSafe.swift) fixed this by making `value` uniquely
// referenced during the call. These tests guard the fix by asserting per-write cost at a
// large preload isn't dramatically worse than at a small one — a regression back to the
// O(n) shape blows past `maxSlowdown` by ~100x; the fix stays under ~5x in practice.
// Bounded by ratio (not absolute time) to stay meaningful across machines/CI load.

private let smallPreload = 1_000
private let largePreload = 200_000
private let writesPerSample = 500
private let maxSlowdown = 20.0

@Test(arguments: mechanisms)
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

@Test(arguments: mechanisms)
func dictionarySetValueCostDoesNotScaleWithCollectionSize(mechanism: ThreadSafeMechanism) {
    let small = ThreadSafe(Dictionary(uniqueKeysWithValues: (0..<smallPreload).map { ($0, $0) }), mechanism: mechanism)
    let smallNsPerOp = averageNanoseconds(over: writesPerSample) { small.setValue(0, forKey: -1) }

    let large = ThreadSafe(Dictionary(uniqueKeysWithValues: (0..<largePreload).map { ($0, $0) }), mechanism: mechanism)
    let largeNsPerOp = averageNanoseconds(over: writesPerSample) { large.setValue(0, forKey: -1) }

    #expect(
        largeNsPerOp < smallNsPerOp * maxSlowdown,
        "setValue at \(largePreload) entries (\(largeNsPerOp) ns/op) is more than \(maxSlowdown)x the cost at \(smallPreload) entries (\(smallNsPerOp) ns/op) — per-write cost is scaling with collection size again"
    )
}
