import Foundation
import Testing

@testable import ThreadSafeKit

// Bounds this library's overhead relative to using the raw, unguarded stdlib type directly —
// answers "how much does thread safety cost here" rather than assertFast's "is this call slow
// in absolute terms." A wrapper can never be *faster* than the raw type it wraps (there's no
// such thing as a free lock), so these tests assert the added cost stays a small, bounded
// multiple of the raw operation instead.

private let mechanisms: [ThreadSafeMechanism] = [.lock, .dispatchQueue]

// MARK: - Array shape

@Test(arguments: mechanisms)
func arrayOverheadReadsAreBounded(mechanism: ThreadSafeMechanism) {
    var raw = [1, 2, 3]
    let wrapped = ThreadSafe(raw, mechanism: mechanism)
    assertOverheadBounded("count", raw: { _ = raw.count }, wrapped: { _ = wrapped.count })
    assertOverheadBounded("subscript(safe:)", raw: { _ = raw.indices.contains(0) ? raw[0] : nil }, wrapped: { _ = wrapped[safe: 0] })
}

@Test(arguments: mechanisms)
func arrayOverheadWritesAreBounded(mechanism: ThreadSafeMechanism) {
    var raw = [1, 2, 3]
    let wrapped = ThreadSafe(raw, mechanism: mechanism)
    assertOverheadBounded(
        "append+removeLast",
        raw: { raw.append(0); raw.removeLast() },
        wrapped: { wrapped.append(0); wrapped.mutate { $0.removeLast() } }
    )
}

// MARK: - Dictionary shape

@Test(arguments: mechanisms)
func dictionaryOverheadReadsAreBounded(mechanism: ThreadSafeMechanism) {
    let raw = ["a": 1, "b": 2]
    let wrapped = ThreadSafe(raw, mechanism: mechanism)
    assertOverheadBounded("subscript(key:) get", raw: { _ = raw["a"] }, wrapped: { _ = wrapped["a"] })
}

@Test(arguments: mechanisms)
func dictionaryOverheadWritesAreBounded(mechanism: ThreadSafeMechanism) {
    var raw = ["a": 1, "b": 2]
    let wrapped = ThreadSafe(raw, mechanism: mechanism)
    assertOverheadBounded(
        "setValue(_:forKey:)",
        raw: { raw["z"] = 1 },
        wrapped: { wrapped.setValue(1, forKey: "z") }
    )
}

// MARK: - Set shape

@Test(arguments: mechanisms)
func setOverheadReadsAreBounded(mechanism: ThreadSafeMechanism) {
    let raw: Set<Int> = [1, 2, 3]
    let wrapped = ThreadSafe(raw, mechanism: mechanism)
    assertOverheadBounded("contains", raw: { _ = raw.contains(1) }, wrapped: { _ = wrapped.contains(1) })
}

@Test(arguments: mechanisms)
func setOverheadWritesAreBounded(mechanism: ThreadSafeMechanism) {
    var raw: Set<Int> = [1, 2, 3]
    let wrapped = ThreadSafe(raw, mechanism: mechanism)
    assertOverheadBounded(
        "insert+remove",
        raw: { raw.insert(99); raw.remove(99) },
        wrapped: { wrapped.insert(99); wrapped.remove(99) }
    )
}

// MARK: - Atomic/scalar shape

@Test(arguments: mechanisms)
func atomicOverheadIsBounded(mechanism: ThreadSafeMechanism) {
    var raw = 0
    let wrapped = ThreadSafe(wrappedValue: 0, mechanism: mechanism)
    assertOverheadBounded("mutate", raw: { raw += 1 }, wrapped: { wrapped.mutate { $0 += 1 } })
}

// MARK: - Actor shapes
//
// Actor calls carry a real Task-hop cost that dwarfs raw synchronous access regardless of what
// the actor's body does, so `assertOverheadBounded`'s async overload uses a much looser
// multiplier/floor — see its doc comment. These still catch a genuine regression inside the
// actor's own logic; they just don't (and can't) hold the actor to the sync wrapper's bar.

@Test
func arrayActorOverheadReadsAreBounded() async {
    var raw = [1, 2, 3]
    let wrapped = ThreadSafeArray([1, 2, 3])
    await assertOverheadBounded("count", raw: { _ = raw.count }, wrapped: { _ = await wrapped.count })
}

@Test
func arrayActorOverheadWritesAreBounded() async {
    var raw = [1, 2, 3]
    let wrapped = ThreadSafeArray([1, 2, 3])
    await assertOverheadBounded(
        "append",
        raw: { raw.append(0); raw.removeLast() },
        wrapped: { await wrapped.append(0); _ = await wrapped.pop() }
    )
}

@Test
func dictionaryActorOverheadReadsAreBounded() async {
    let raw = ["a": 1, "b": 2]
    let wrapped = ThreadSafeDictionary(["a": 1, "b": 2])
    await assertOverheadBounded("getValue(forKey:)", raw: { _ = raw["a"] }, wrapped: { _ = await wrapped.getValue(forKey: "a") })
}

@Test
func dictionaryActorOverheadWritesAreBounded() async {
    var raw = ["a": 1, "b": 2]
    let wrapped = ThreadSafeDictionary(["a": 1, "b": 2])
    await assertOverheadBounded(
        "setValue(_:forKey:)",
        raw: { raw["z"] = 1 },
        wrapped: { await wrapped.setValue(1, forKey: "z") }
    )
}

@Test
func setActorOverheadReadsAreBounded() async {
    let raw: Set<Int> = [1, 2, 3]
    let wrapped = ThreadSafeSet([1, 2, 3])
    await assertOverheadBounded("contains", raw: { _ = raw.contains(1) }, wrapped: { _ = await wrapped.contains(1) })
}

@Test
func setActorOverheadWritesAreBounded() async {
    var raw: Set<Int> = [1, 2, 3]
    let wrapped = ThreadSafeSet([1, 2, 3])
    await assertOverheadBounded(
        "insert+remove",
        raw: { raw.insert(99); raw.remove(99) },
        wrapped: { await wrapped.insert(99); _ = await wrapped.remove(99) }
    )
}

@Test
func atomicActorOverheadIsBounded() async {
    var raw = 0
    let wrapped = ThreadSafeAtomic(0)
    await assertOverheadBounded("mutate", raw: { raw += 1 }, wrapped: { await wrapped.mutate { $0 += 1 } })
}
