import Foundation
import Testing
@testable import ThreadSafeKit

private let mechanisms: [ThreadSafeMechanism] = [.lock, .readerWriterLock]

@Test(arguments: mechanisms) func threadSafeDictionarySetAndGet(mechanism: ThreadSafeMechanism) throws {
    let dictionary = ThreadSafe<[String: Int]>(mechanism: mechanism)
    dictionary["answer"] = 42
    #expect(dictionary["answer"] == 42)
    #expect(dictionary.count == 1)
}

@Test(arguments: mechanisms) func threadSafeDictionaryInitWithDictionary(mechanism: ThreadSafeMechanism) throws {
    let dictionary = ThreadSafe(["a": 1, "b": 2], mechanism: mechanism)
    #expect(dictionary.count == 2)
    #expect(dictionary["a"] == 1)
}

@Test(arguments: mechanisms) func threadSafeDictionaryIsEmptyAndDictionaryProperty(mechanism: ThreadSafeMechanism) throws {
    let empty = ThreadSafe<[String: Int]>(mechanism: mechanism)
    #expect(empty.isEmpty)

    let dictionary = ThreadSafe(["a": 1], mechanism: mechanism)
    #expect(dictionary.isEmpty == false)
    #expect(dictionary.dictionary == ["a": 1])
}

@Test(arguments: mechanisms) func threadSafeDictionaryRemoveValue(mechanism: ThreadSafeMechanism) throws {
    let dictionary = ThreadSafe(["a": 1], mechanism: mechanism)
    let removed = dictionary.removeValue(forKey: "a")
    #expect(removed == 1)
    #expect(dictionary.isEmpty)
}

@Test(arguments: mechanisms) func threadSafeDictionaryRemoveAll(mechanism: ThreadSafeMechanism) throws {
    let dictionary = ThreadSafe(["a": 1, "b": 2], mechanism: mechanism)
    dictionary.removeAll()
    #expect(dictionary.isEmpty)
}

@Test(arguments: mechanisms) func threadSafeDictionaryMerge(mechanism: ThreadSafeMechanism) throws {
    let dictionary = ThreadSafe(["a": 1], mechanism: mechanism)
    dictionary.merge(["a": 2, "b": 3]) { _, new in new }
    #expect(dictionary.dictionary == ["a": 2, "b": 3])
}

@Test(arguments: mechanisms) func threadSafeDictionaryUpdateValue(mechanism: ThreadSafeMechanism) throws {
    let dictionary = ThreadSafe(["a": 1], mechanism: mechanism)
    #expect(dictionary.updateValue(2, forKey: "a") == 1)
    #expect(dictionary.updateValue(3, forKey: "b") == nil)
    #expect(dictionary.dictionary == ["a": 2, "b": 3])
}

@Test(arguments: mechanisms) func threadSafeDictionaryKeysAndValues(mechanism: ThreadSafeMechanism) throws {
    let dictionary = ThreadSafe(["a": 1, "b": 2], mechanism: mechanism)
    #expect(Set(dictionary.keys) == ["a", "b"])
    #expect(Set(dictionary.values) == [1, 2])
}

// `keys`/`values` return the same view types as a plain `Dictionary`'s own `keys`/`values`,
// not `[Key]`/`[Value]` — this pins the static type so a regression back to an `Array` return
// would fail to compile, not just fail an equality check.
@Test(arguments: mechanisms) func threadSafeDictionaryKeysAndValuesAreStandardViewTypes(mechanism: ThreadSafeMechanism) throws {
    let dictionary = ThreadSafe(["a": 1, "b": 2], mechanism: mechanism)
    let keys: Dictionary<String, Int>.Keys = dictionary.keys
    let values: Dictionary<String, Int>.Values = dictionary.values
    #expect(Set(keys) == ["a", "b"])
    #expect(Set(values) == [1, 2])
}

@Test(arguments: mechanisms) func threadSafeDictionaryMapValues(mechanism: ThreadSafeMechanism) throws {
    let dictionary = ThreadSafe(["a": 1, "b": 2], mechanism: mechanism)
    #expect(dictionary.mapValues { $0 * 10 } == ["a": 10, "b": 20])
}

@Test(arguments: mechanisms) func threadSafeDictionaryCompactMapValues(mechanism: ThreadSafeMechanism) throws {
    let dictionary = ThreadSafe(["a": 1, "b": 2], mechanism: mechanism)
    #expect(dictionary.compactMapValues { $0 == 1 ? nil : $0 } == ["b": 2])
}

@Test(arguments: mechanisms) func threadSafeDictionaryFilter(mechanism: ThreadSafeMechanism) throws {
    let dictionary = ThreadSafe(["a": 1, "b": 2], mechanism: mechanism)
    #expect(dictionary.filter { $0.value > 1 } == ["b": 2])
}

@Test(arguments: mechanisms) func threadSafeDictionaryContainsWhere(mechanism: ThreadSafeMechanism) throws {
    let dictionary = ThreadSafe(["a": 1, "b": 2], mechanism: mechanism)
    #expect(dictionary.contains { $0.value == 2 })
    #expect(dictionary.contains { $0.value == 3 } == false)
}

@Test(arguments: mechanisms) func threadSafeDictionaryForEach(mechanism: ThreadSafeMechanism) throws {
    let dictionary = ThreadSafe(["a": 1, "b": 2], mechanism: mechanism)
    let sum = ThreadSafe(wrappedValue: 0)
    dictionary.forEach { entry in sum.mutate { $0 += entry.value } }
    #expect(sum.wrappedValue == 3)
}

@Test(arguments: mechanisms) func threadSafeDictionaryReduce(mechanism: ThreadSafeMechanism) throws {
    let dictionary = ThreadSafe(["a": 1, "b": 2], mechanism: mechanism)
    let sum = dictionary.reduce(into: 0) { result, entry in result += entry.value }
    #expect(sum == 3)
}

@Test(arguments: mechanisms) func threadSafeDictionarySubscript(mechanism: ThreadSafeMechanism) throws {
    let dictionary = ThreadSafe<[String: Int]>(mechanism: mechanism)
    dictionary["a"] = 1
    #expect(dictionary["a"] == 1)
}

@Test(arguments: mechanisms) func threadSafeDictionarySubscriptNilRemoves(mechanism: ThreadSafeMechanism) throws {
    let dictionary = ThreadSafe(["a": 1], mechanism: mechanism)
    dictionary["a"] = nil
    #expect(dictionary.isEmpty)
}

@Test(arguments: mechanisms) func threadSafeDictionaryConcurrentSetsDoNotDropWrites(mechanism: ThreadSafeMechanism) throws {
    let dictionary = ThreadSafe<[Int: Int]>(mechanism: mechanism)
    DispatchQueue.concurrentPerform(iterations: concurrencyIterations) { i in
        dictionary[i] = i
    }
    #expect(dictionary.count == concurrencyIterations)
}

// `dict["k"]! += 1` holds the write lock across the whole get-modify-set (see the subscript's
// doc comment in ThreadSafe+Dictionary.swift) — unlike the old get/set-accessor subscript,
// concurrent compound assignment through it can't lose updates.
//
// 8 workers each doing many *sequential* increments (rather than one `concurrentPerform`
// iteration per increment) — matching the array equivalent of this test.
@Test(arguments: mechanisms) func threadSafeDictionarySubscriptCompoundAssignmentIsAtomic(mechanism: ThreadSafeMechanism) throws {
    let dictionary = ThreadSafe(["k": 0], mechanism: mechanism)
    let workers = 8
    let perWorker = 250
    DispatchQueue.concurrentPerform(iterations: workers) { _ in
        for _ in 0..<perWorker { dictionary["k"]! += 1 }
    }
    #expect(dictionary["k"] == workers * perWorker)
}

// Same atomicity, but for the "keyed collection value" shape (`lists["k"]?.append(i)`) rather
// than a keyed scalar — the subscript's `_modify` holds the lock across the whole optional-chained
// mutation just as it does for `!` above.
@Test(arguments: mechanisms) func threadSafeDictionaryOfArraysSubscriptOptionalAppendIsAtomic(mechanism: ThreadSafeMechanism) throws {
    let lists = ThreadSafe(["k": [Int]()], mechanism: mechanism)
    let workers = 8
    let perWorker = 250
    DispatchQueue.concurrentPerform(iterations: workers) { w in
        for j in 0..<perWorker { lists["k"]?.append(w * perWorker + j) }
    }
    #expect(lists["k"]?.count == workers * perWorker)
}

// `lists["missing"]?.append(x)` on a key that was never inserted must be a no-op — the yielded
// value is `nil`, `Optional.append` never runs, and writing `nil` back through the subscript's
// setter doesn't insert a "nil" entry (removing an absent key is itself a no-op for `Dictionary`).
@Test(arguments: mechanisms) func threadSafeDictionaryOfArraysOptionalAppendOnMissingKeyIsNoOp(mechanism: ThreadSafeMechanism) throws {
    let lists = ThreadSafe<[String: [Int]]>(mechanism: mechanism)
    lists["missing"]?.append(1)
    #expect(lists.isEmpty)
    #expect(lists["missing"] == nil)
}

// Interleaves reads with writes to exercise the backing mechanism specifically: whether it's the
// unfair lock (all access exclusive) or the concurrent queue + barrier (concurrent readers, exclusive
// writers), concurrent readers and writers still can't race. A real race here is caught by Thread
// Sanitizer (`swift test --sanitize=thread`), not just by a dropped-write count.
@Test(arguments: mechanisms) func threadSafeDictionaryConcurrentReadsDuringWritesDoNotRace(mechanism: ThreadSafeMechanism) throws {
    let dictionary = ThreadSafe<[Int: Int]>(mechanism: mechanism)
    DispatchQueue.concurrentPerform(iterations: concurrencyIterations * 2) { i in
        if i % 2 == 0 {
            dictionary[i] = i
        } else {
            _ = dictionary.count
            _ = dictionary.dictionary
            _ = dictionary[0]
        }
    }
    #expect(dictionary.count == concurrencyIterations)
}

@Test(arguments: mechanisms) func threadSafeDictionaryMutateReturnsValueAndMutates(mechanism: ThreadSafeMechanism) throws {
    let dictionary = ThreadSafe(["a": 1], mechanism: mechanism)
    let removed = dictionary.mutate { storage in
        storage["b"] = 2
        return storage.removeValue(forKey: "a")
    }
    #expect(removed == 1)
    #expect(dictionary.dictionary == ["b": 2])
}

// Each iteration reads the current counter value then writes back the increment
// (check-then-act). If `mutate` didn't hold the lock/queue for the whole closure,
// concurrent increments could race and lose updates.
@Test(arguments: mechanisms) func threadSafeDictionaryMutateIsAtomicAcrossCompoundOperations(mechanism: ThreadSafeMechanism) throws {
    let dictionary = ThreadSafe<[String: Int]>(mechanism: mechanism)
    DispatchQueue.concurrentPerform(iterations: concurrencyIterations) { _ in
        dictionary.mutate { storage in
            storage["counter", default: 0] += 1
        }
    }
    #expect(dictionary["counter"] == concurrencyIterations)
}

@Test(arguments: mechanisms) func threadSafeDictionaryCodableRoundTrip(mechanism: ThreadSafeMechanism) throws {
    let dictionary = ThreadSafe(["a": 1, "b": 2], mechanism: mechanism)
    let data = try JSONEncoder().encode(dictionary)
    let decoded = try JSONDecoder().decode(ThreadSafe<[String: Int]>.self, from: data)
    #expect(decoded.dictionary == ["a": 1, "b": 2])
}

// Auto-synthesized Codable on a containing type only compiles because
// ThreadSafe<[String: Int]> conforms to Codable; this is the whole point of the feature.
@Test func threadSafeDictionaryCodableRoundTripInsideContainingType() throws {
    struct Container: Codable {
        let values: ThreadSafe<[String: Int]>
    }
    let container = Container(values: ThreadSafe(["a": 1]))
    let data = try JSONEncoder().encode(container)
    let decoded = try JSONDecoder().decode(Container.self, from: data)
    #expect(decoded.values.dictionary == ["a": 1])
}

@Test func threadSafeDictionaryEquatableComparesDictionary() throws {
    #expect(ThreadSafe(["a": 1]) == ThreadSafe(["a": 1]))
    #expect(ThreadSafe(["a": 1]) != ThreadSafe(["a": 2]))
    #expect(ThreadSafe(["a": 1]) != ThreadSafe(["a": 1, "b": 2]))
}

// Auto-synthesized Equatable on a containing type only compiles because
// ThreadSafe<[String: Int]> conforms to Equatable; this is the whole point of the feature.
@Test func threadSafeDictionaryEquatableInsideContainingType() throws {
    struct Container: Equatable {
        let values: ThreadSafe<[String: Int]>
    }
    #expect(Container(values: ThreadSafe(["a": 1])) == Container(values: ThreadSafe(["a": 1])))
    #expect(Container(values: ThreadSafe(["a": 1])) != Container(values: ThreadSafe(["a": 2])))
}

@Test(arguments: mechanisms) func threadSafeDictionaryDescriptionContainsDictionary(mechanism: ThreadSafeMechanism) throws {
    #expect(ThreadSafe(["a": 1], mechanism: mechanism).description == "ThreadSafe([\"a\": 1])")
}

@Test(arguments: mechanisms) func threadSafeDictionaryPropertyWrapperReadsSnapshotAndProjectsInstance(mechanism: ThreadSafeMechanism) throws {
    @ThreadSafe(mechanism: mechanism) var values = ["a": 1]
    #expect(values == ["a": 1])
    $values["b"] = 2
    #expect(values == ["a": 1, "b": 2])
    #expect($values.count == 2)
}

