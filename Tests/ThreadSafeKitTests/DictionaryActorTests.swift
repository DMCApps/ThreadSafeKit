import Foundation
import Testing
@testable import ThreadSafeKit

@Test func dictionaryActorSetAndGet() async throws {
    let dictionary = DictionaryActor<String, Int>()
    await dictionary.setValue(42, forKey: "answer")
    #expect(await dictionary.getValue(forKey: "answer") == 42)
    #expect(await dictionary.count == 1)
}

@Test func dictionaryActorInitWithDictionary() async throws {
    let dictionary = DictionaryActor(["a": 1, "b": 2])
    #expect(await dictionary.count == 2)
    #expect(await dictionary.getValue(forKey: "a") == 1)
}

@Test func dictionaryActorIsEmptyAndDictionaryProperty() async throws {
    let empty = DictionaryActor<String, Int>()
    #expect(await empty.isEmpty)

    let dictionary = DictionaryActor(["a": 1])
    #expect(await dictionary.isEmpty == false)
    #expect(await dictionary.dictionary == ["a": 1])
}

@Test func dictionaryActorRemoveValue() async throws {
    let dictionary = DictionaryActor(["a": 1])
    let removed = await dictionary.removeValue(forKey: "a")
    #expect(removed == 1)
    #expect(await dictionary.isEmpty)
}

@Test func dictionaryActorRemoveAll() async throws {
    let dictionary = DictionaryActor(["a": 1, "b": 2])
    await dictionary.removeAll()
    #expect(await dictionary.isEmpty)
}

@Test func dictionaryActorMerge() async throws {
    let dictionary = DictionaryActor(["a": 1])
    await dictionary.merge(["a": 2, "b": 3]) { _, new in new }
    #expect(await dictionary.dictionary == ["a": 2, "b": 3])
}

@Test func dictionaryActorForEach() async throws {
    let dictionary = DictionaryActor(["a": 1, "b": 2])
    let sum = Atomic(wrappedValue: 0)
    await dictionary.forEach { entry in sum.mutate { $0 += entry.value } }
    #expect(sum.wrappedValue == 3)
}

@Test func dictionaryActorReduce() async throws {
    let dictionary = DictionaryActor(["a": 1, "b": 2])
    let sum = await dictionary.reduce(into: 0) { result, entry in result += entry.value }
    #expect(sum == 3)
}

@Test func dictionaryActorSubscript() async throws {
    let dictionary = DictionaryActor<String, Int>()
    await dictionary.setValue(1, forKey: "a")
    #expect(await dictionary["a"] == 1)
}

@Test func dictionaryActorSubscriptNilRemoves() async throws {
    let dictionary = DictionaryActor(["a": 1])
    await dictionary.setValue(nil, forKey: "a")
    #expect(await dictionary.isEmpty)
}

@Test func dictionaryActorConcurrentSetsDoNotDropWrites() async throws {
    let dictionary = DictionaryActor<Int, Int>()
    await withTaskGroup(of: Void.self) { group in
        for i in 0..<concurrencyIterations {
            group.addTask { await dictionary.setValue(i, forKey: i) }
        }
    }
    #expect(await dictionary.count == concurrencyIterations)
}

// Interleaves reads with writes (not just writes vs writes), proving mixed
// operations don't deadlock or corrupt state under actor reentrancy. A real
// race here is caught by Thread Sanitizer (`swift test --sanitize=thread`),
// not just by a dropped-write count.
@Test func dictionaryActorConcurrentReadsDuringWritesDoNotRace() async throws {
    let dictionary = DictionaryActor<Int, Int>()
    await withTaskGroup(of: Void.self) { group in
        for i in 0..<(concurrencyIterations * 2) {
            group.addTask {
                if i % 2 == 0 {
                    await dictionary.setValue(i, forKey: i)
                } else {
                    _ = await dictionary.count
                    _ = await dictionary.dictionary
                    _ = await dictionary.getValue(forKey: 0)
                }
            }
        }
    }
    #expect(await dictionary.count == concurrencyIterations)
}

@Test func dictionaryActorMutateReturnsValueAndMutates() async throws {
    let dictionary = DictionaryActor(["a": 1])
    let removed = await dictionary.mutate { storage in
        storage["b"] = 2
        return storage.removeValue(forKey: "a")
    }
    #expect(removed == 1)
    #expect(await dictionary.dictionary == ["b": 2])
}

// Each task reads the current counter value then writes back the increment
// (check-then-act). If `mutate` didn't hold the actor for the whole closure,
// concurrent increments could race and lose updates.
@Test func dictionaryActorMutateIsAtomicAcrossCompoundOperations() async throws {
    let dictionary = DictionaryActor<String, Int>()
    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<concurrencyIterations {
            group.addTask {
                await dictionary.mutate { storage in
                    storage["counter", default: 0] += 1
                }
            }
        }
    }
    #expect(await dictionary.getValue(forKey: "counter") == concurrencyIterations)
}

// Demonstrates the exact problem `mutate` fixes: reading then setting as two
// separate actor calls lets both reads observe the same stale value, losing
// an update. A single `mutate` call doesn't have this problem because both
// steps happen under one actor call.
@Test func dictionaryActorSeparateGetAndSetCanLoseUpdates() async throws {
    let dictionary = DictionaryActor<String, Int>()
    let a = await dictionary.getValue(forKey: "counter") ?? 0
    let b = await dictionary.getValue(forKey: "counter") ?? 0
    await dictionary.setValue(a + 1, forKey: "counter")
    await dictionary.setValue(b + 1, forKey: "counter")
    #expect(await dictionary.getValue(forKey: "counter") == 1)
}
