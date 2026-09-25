import Testing

@testable import ThreadSafeKit

// Absolute-time ceilings for every `ThreadSafeDictionary` member.

@Test(.tags(.performance))
func dictionaryActorReadsAreFast() async {
    let dictionary = ThreadSafeDictionary(["a": 1, "b": 2])
    await assertFast("count") { _ = await dictionary.count }
    await assertFast("isEmpty") { _ = await dictionary.isEmpty }
    await assertFast("dictionary") { _ = await dictionary.dictionary }
    await assertFast("subscript(key:) get") { _ = await dictionary["a"] }
    await assertFast("forEach") { await dictionary.forEach { _ = $0 } }
    await assertFast("reduce") { _ = await dictionary.reduce(into: 0) { $0 += $1.value } }
    await assertFast("keys") { _ = await dictionary.keys }
    await assertFast("values") { _ = await dictionary.values }
    await assertFast("mapValues") { _ = await dictionary.mapValues { $0 } }
    await assertFast("compactMapValues") { _ = await dictionary.compactMapValues { $0 } }
    await assertFast("filter") { _ = await dictionary.filter { $0.value > 0 } }
    await assertFast("contains(where:)") { _ = await dictionary.contains { $0.value > 0 } }
}

@Test(.tags(.performance))
func dictionaryActorWritesAreFast() async {
    let dictionary = ThreadSafeDictionary(["a": 1, "b": 2])
    await assertFast("removeValue(forKey:)") { _ = await dictionary.removeValue(forKey: "does-not-exist") }
    await assertFast("updateValue(_:forKey:)") { _ = await dictionary.updateValue(1, forKey: "z") }
    await assertFast("merge") { await dictionary.merge(["y": 1]) { old, _ in old } }
    await assertFast("mutate") { await dictionary.mutate { $0["z"] = 1 } }
}

@Test(.tags(.performance))
func dictionaryActorRemoveAllIsFast() async {
    let dictionary = ThreadSafeDictionary(["a": 1, "b": 2])
    await assertFast("removeAll") { await dictionary.removeAll() }
}
