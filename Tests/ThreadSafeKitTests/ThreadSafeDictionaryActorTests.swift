import Foundation
import Testing
@testable import ThreadSafeKit

@Test func dictionaryActorSetAndGet() async throws {
    let dictionary = ThreadSafeDictionary<String, Int>()
    await dictionary.updateValue(42, forKey: "answer")
    #expect(await dictionary["answer"] == 42)
    #expect(await dictionary.count == 1)
}

@Test func dictionaryActorInitWithDictionary() async throws {
    let dictionary = ThreadSafeDictionary(["a": 1, "b": 2])
    #expect(await dictionary.count == 2)
    #expect(await dictionary["a"] == 1)
}

@Test func dictionaryActorIsEmptyAndDictionaryProperty() async throws {
    let empty = ThreadSafeDictionary<String, Int>()
    #expect(await empty.isEmpty)

    let dictionary = ThreadSafeDictionary(["a": 1])
    #expect(await dictionary.isEmpty == false)
    #expect(await dictionary.dictionary == ["a": 1])
}

@Test func dictionaryActorRemoveValue() async throws {
    let dictionary = ThreadSafeDictionary(["a": 1])
    let removed = await dictionary.removeValue(forKey: "a")
    #expect(removed == 1)
    #expect(await dictionary.isEmpty)
}

@Test func dictionaryActorRemoveAll() async throws {
    let dictionary = ThreadSafeDictionary(["a": 1, "b": 2])
    await dictionary.removeAll()
    #expect(await dictionary.isEmpty)
}

@Test func dictionaryActorMerge() async throws {
    let dictionary = ThreadSafeDictionary(["a": 1])
    await dictionary.merge(["a": 2, "b": 3]) { _, new in new }
    #expect(await dictionary.dictionary == ["a": 2, "b": 3])
}

@Test func dictionaryActorUpdateValue() async throws {
    let dictionary = ThreadSafeDictionary(["a": 1])
    #expect(await dictionary.updateValue(2, forKey: "a") == 1)
    #expect(await dictionary.updateValue(3, forKey: "b") == nil)
    #expect(await dictionary.dictionary == ["a": 2, "b": 3])
}

@Test func dictionaryActorKeysAndValues() async throws {
    let dictionary = ThreadSafeDictionary(["a": 1, "b": 2])
    #expect(await Set(dictionary.keys) == ["a", "b"])
    #expect(await Set(dictionary.values) == [1, 2])
}

@Test func dictionaryActorMapValues() async throws {
    let dictionary = ThreadSafeDictionary(["a": 1, "b": 2])
    #expect(await dictionary.mapValues { $0 * 10 } == ["a": 10, "b": 20])
}

@Test func dictionaryActorCompactMapValues() async throws {
    let dictionary = ThreadSafeDictionary(["a": 1, "b": 2])
    #expect(await dictionary.compactMapValues { $0 == 1 ? nil : $0 } == ["b": 2])
}

@Test func dictionaryActorFilter() async throws {
    let dictionary = ThreadSafeDictionary(["a": 1, "b": 2])
    #expect(await dictionary.filter { $0.value > 1 } == ["b": 2])
}

@Test func dictionaryActorContainsWhere() async throws {
    let dictionary = ThreadSafeDictionary(["a": 1, "b": 2])
    #expect(await dictionary.contains { $0.value == 2 })
    #expect(await dictionary.contains { $0.value == 3 } == false)
}

@Test func dictionaryActorForEach() async throws {
    let dictionary = ThreadSafeDictionary(["a": 1, "b": 2])
    let sum = ThreadSafe(wrappedValue: 0)
    await dictionary.forEach { entry in sum.mutate { $0 += entry.value } }
    #expect(sum.wrappedValue == 3)
}

@Test func dictionaryActorReduce() async throws {
    let dictionary = ThreadSafeDictionary(["a": 1, "b": 2])
    let sum = await dictionary.reduce(into: 0) { result, entry in result += entry.value }
    #expect(sum == 3)
}

@Test func dictionaryActorSubscript() async throws {
    let dictionary = ThreadSafeDictionary<String, Int>()
    await dictionary.updateValue(1, forKey: "a")
    #expect(await dictionary["a"] == 1)
}

@Test func dictionaryActorRemoveValueRemoves() async throws {
    let dictionary = ThreadSafeDictionary(["a": 1])
    await dictionary.removeValue(forKey: "a")
    #expect(await dictionary.isEmpty)
}

@Test func dictionaryActorConcurrentSetsDoNotDropWrites() async throws {
    let dictionary = ThreadSafeDictionary<Int, Int>()
    await withTaskGroup(of: Void.self) { group in
        for i in 0..<concurrencyIterations {
            group.addTask { await dictionary.updateValue(i, forKey: i) }
        }
    }
    #expect(await dictionary.count == concurrencyIterations)
}

// Mixed concurrent reads and writes must not corrupt state; run under TSan to catch races.
@Test func dictionaryActorConcurrentReadsDuringWritesDoNotRace() async throws {
    let dictionary = ThreadSafeDictionary<Int, Int>()
    await withTaskGroup(of: Void.self) { group in
        for i in 0..<(concurrencyIterations * 2) {
            group.addTask {
                if i % 2 == 0 {
                    await dictionary.updateValue(i, forKey: i)
                } else {
                    _ = await dictionary.count
                    _ = await dictionary.dictionary
                    _ = await dictionary[0]
                }
            }
        }
    }
    #expect(await dictionary.count == concurrencyIterations)
}

@Test func dictionaryActorMutateReturnsValueAndMutates() async throws {
    let dictionary = ThreadSafeDictionary(["a": 1])
    let removed = await dictionary.mutate { storage in
        storage["b"] = 2
        return storage.removeValue(forKey: "a")
    }
    #expect(removed == 1)
    #expect(await dictionary.dictionary == ["b": 2])
}

// Check-then-act increments inside `mutate` must not lose updates.
@Test func dictionaryActorMutateIsAtomicAcrossCompoundOperations() async throws {
    let dictionary = ThreadSafeDictionary<String, Int>()
    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<concurrencyIterations {
            group.addTask {
                await dictionary.mutate { storage in
                    storage["counter", default: 0] += 1
                }
            }
        }
    }
    #expect(await dictionary["counter"] == concurrencyIterations)
}

@Test func dictionaryActorSubscriptDefault() async throws {
    let dictionary = ThreadSafeDictionary(["a": 1])
    #expect(await dictionary["a", default: 0] == 1)
    #expect(await dictionary["missing", default: 0] == 0)
}

// The actor's default subscript is get-only, so concurrent default-and-update goes through `mutate`.
@Test func dictionaryActorSubscriptDefaultViaMutateIsAtomic() async throws {
    let dictionary = ThreadSafeDictionary<String, Int>()
    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<concurrencyIterations {
            group.addTask {
                await dictionary.mutate { $0["counter", default: 0] += 1 }
            }
        }
    }
    #expect(await dictionary["counter"] == concurrencyIterations)
}

@Test func dictionaryActorPopFirst() async throws {
    let dictionary = ThreadSafeDictionary(["a": 1])
    let popped = await dictionary.popFirst()
    #expect(popped?.key == "a")
    #expect(popped?.value == 1)
    #expect(await dictionary.isEmpty)

    let empty = ThreadSafeDictionary<String, Int>()
    #expect(await empty.popFirst() == nil)
}

// Concurrent drains must remove every entry exactly once — no duplicates, no drops.
@Test func dictionaryActorConcurrentPopFirstDrainsExactlyOnce() async throws {
    let n = 2_000
    let dictionary = ThreadSafeDictionary(Dictionary(uniqueKeysWithValues: (0..<n).map { ($0, $0 * 2) }))
    let popped = ThreadSafeArray<Int>()
    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<8 {
            group.addTask {
                while let (key, value) = await dictionary.popFirst() {
                    #expect(value == key * 2)
                    await popped.append(key)
                }
            }
        }
    }
    #expect(await dictionary.isEmpty)
    let drained = await popped.elements
    #expect(drained.count == n)
    #expect(Set(drained) == Set(0..<n))
}

@Test func dictionaryActorReserveCapacity() async throws {
    let dictionary = ThreadSafeDictionary(["a": 1, "b": 2])
    await dictionary.reserveCapacity(100)
    #expect(await dictionary.dictionary == ["a": 1, "b": 2])
}

// Concurrent `reserveCapacity` must not drop concurrent writes.
@Test func dictionaryActorConcurrentReserveCapacityDoesNotCorruptConcurrentWrites() async throws {
    let dictionary = ThreadSafeDictionary<Int, Int>()
    let n = concurrencyIterations
    await withTaskGroup(of: Void.self) { group in
        for i in 0..<n {
            group.addTask { await dictionary.updateValue(i, forKey: i) }
        }
        for _ in 0..<n {
            group.addTask { await dictionary.reserveCapacity(1_000) }
        }
    }
    #expect(await dictionary.count == n)
    let snapshot = await dictionary.dictionary
    #expect(snapshot.allSatisfy { $0.value == $0.key })
}

@Test func dictionaryActorMergeSequenceOfPairs() async throws {
    let dictionary = ThreadSafeDictionary(["a": 1])
    await dictionary.merge([("a", 2), ("b", 3)]) { _, new in new }
    #expect(await dictionary.dictionary == ["a": 2, "b": 3])
}

// Disjoint key ranges, so this only checks for lost writes.
@Test func dictionaryActorConcurrentMergeSequenceOfPairsPreservesEveryEntry() async throws {
    let dictionary = ThreadSafeDictionary<Int, Int>()
    let writers = 8
    let perWriter = 250
    await withTaskGroup(of: Void.self) { group in
        for w in 0..<writers {
            group.addTask {
                let pairs = (0..<perWriter).map { (w * perWriter + $0, w) }
                await dictionary.merge(pairs) { _, new in new }
            }
        }
    }
    #expect(await dictionary.count == writers * perWriter)
}

@Test func dictionaryActorFirstWhere() async throws {
    let dictionary = ThreadSafeDictionary(["a": 1, "b": 2])
    #expect(await dictionary.first(where: { $0.value == 2 })?.key == "b")
    #expect(await dictionary.first(where: { $0.value == 3 }) == nil)
}

@Test func dictionaryActorCountWhere() async throws {
    let dictionary = ThreadSafeDictionary(["a": 1, "b": 2, "c": 3])
    #expect(await dictionary.count(where: { $0.value > 1 }) == 2)
}

@Test func dictionaryActorMinByAndMaxBy() async throws {
    let dictionary = ThreadSafeDictionary(["a": 3, "b": 1, "c": 2])
    #expect(await dictionary.min(by: { $0.value < $1.value })?.key == "b")
    #expect(await dictionary.max(by: { $0.value < $1.value })?.key == "a")
}

@Test func dictionaryActorReduceNonInto() async throws {
    let dictionary = ThreadSafeDictionary(["a": 1, "b": 2])
    let sum = await dictionary.reduce(0) { $0 + $1.value }
    #expect(sum == 3)
}

@Test func dictionaryActorRandomElement() async throws {
    let dictionary = ThreadSafeDictionary(["a": 1, "b": 2])
    let element = await dictionary.randomElement()
    #expect(element != nil)
    #expect(["a", "b"].contains(element!.key))

    let empty = ThreadSafeDictionary<String, Int>()
    #expect(await empty.randomElement() == nil)
}

@Test func dictionaryActorAllSatisfy() async throws {
    let dictionary = ThreadSafeDictionary(["a": 2, "b": 4])
    #expect(await dictionary.allSatisfy { $0.value % 2 == 0 })
    #expect(await dictionary.allSatisfy { $0.value > 2 } == false)
}

@Test func dictionaryActorCompactMap() async throws {
    let dictionary = ThreadSafeDictionary(["a": 1, "b": 2])
    let values = await dictionary.compactMap { $0.value == 1 ? nil : $0.value }
    #expect(values == [2])
}

@Test func dictionaryActorSortedBy() async throws {
    let dictionary = ThreadSafeDictionary(["a": 3, "b": 1, "c": 2])
    let sorted = await dictionary.sorted(by: { $0.value < $1.value })
    #expect(sorted.map(\.key) == ["b", "c", "a"])
}

@Test func dictionaryActorMap() async throws {
    let dictionary = ThreadSafeDictionary(["a": 1, "b": 2])
    let doubled = await dictionary.map { $0.value * 2 }
    #expect(Set(doubled) == [2, 4])
}
