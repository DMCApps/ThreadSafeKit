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

// Pins `keys`/`values` to Dictionary's view types, not arrays.
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

// `dict["k"]! += 1` holds the write lock across get-modify-set, so no increments are lost.
@Test(arguments: mechanisms) func threadSafeDictionarySubscriptCompoundAssignmentIsAtomic(mechanism: ThreadSafeMechanism) throws {
    let dictionary = ThreadSafe(["k": 0], mechanism: mechanism)
    let workers = 8
    let perWorker = 250
    DispatchQueue.concurrentPerform(iterations: workers) { _ in
        for _ in 0..<perWorker { dictionary["k"]! += 1 }
    }
    #expect(dictionary["k"] == workers * perWorker)
}

// Optional-chained mutation through `_modify` is atomic too.
@Test(arguments: mechanisms) func threadSafeDictionaryOfArraysSubscriptOptionalAppendIsAtomic(mechanism: ThreadSafeMechanism) throws {
    let lists = ThreadSafe(["k": [Int]()], mechanism: mechanism)
    let workers = 8
    let perWorker = 250
    DispatchQueue.concurrentPerform(iterations: workers) { w in
        for j in 0..<perWorker { lists["k"]?.append(w * perWorker + j) }
    }
    #expect(lists["k"]?.count == workers * perWorker)
}

// Optional chaining on a missing key must not insert it.
@Test(arguments: mechanisms) func threadSafeDictionaryOfArraysOptionalAppendOnMissingKeyIsNoOp(mechanism: ThreadSafeMechanism) throws {
    let lists = ThreadSafe<[String: [Int]]>(mechanism: mechanism)
    lists["missing"]?.append(1)
    #expect(lists.isEmpty)
    #expect(lists["missing"] == nil)
}

// Mixed concurrent reads and writes must not corrupt state; run under TSan to catch races.
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

// Check-then-act increments inside `mutate` must not lose updates.
@Test(arguments: mechanisms) func threadSafeDictionaryMutateIsAtomicAcrossCompoundOperations(mechanism: ThreadSafeMechanism) throws {
    let dictionary = ThreadSafe<[String: Int]>(mechanism: mechanism)
    DispatchQueue.concurrentPerform(iterations: concurrencyIterations) { _ in
        dictionary.mutate { storage in
            storage["counter", default: 0] += 1
        }
    }
    #expect(dictionary["counter"] == concurrencyIterations)
}

@Test func threadSafeDictionaryEquatableComparesDictionary() throws {
    #expect(ThreadSafe(["a": 1]) == ThreadSafe(["a": 1]))
    #expect(ThreadSafe(["a": 1]) != ThreadSafe(["a": 2]))
    #expect(ThreadSafe(["a": 1]) != ThreadSafe(["a": 1, "b": 2]))
}

// Compiles only because `ThreadSafe<[String: Int]>` is Equatable.
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

@Test(arguments: mechanisms) func threadSafeDictionarySubscriptDefault(mechanism: ThreadSafeMechanism) throws {
    let dictionary = ThreadSafe(["a": 1], mechanism: mechanism)
    #expect(dictionary["a", default: 0] == 1)
    #expect(dictionary["missing", default: 0] == 0)
    dictionary["missing", default: 0] += 5
    #expect(dictionary["missing"] == 5)
}

// Concurrent `d[k, default: 0] += 1` on a new key must sum exactly.
@Test(arguments: mechanisms) func threadSafeDictionarySubscriptDefaultCompoundAssignmentIsAtomic(mechanism: ThreadSafeMechanism) throws {
    let dictionary = ThreadSafe<[String: Int]>(mechanism: mechanism)
    let workers = 8
    let perWorker = 250
    DispatchQueue.concurrentPerform(iterations: workers) { _ in
        for _ in 0..<perWorker { dictionary["counter", default: 0] += 1 }
    }
    #expect(dictionary["counter"] == workers * perWorker)
}

@Test(arguments: mechanisms) func threadSafeDictionaryPopFirst(mechanism: ThreadSafeMechanism) throws {
    let dictionary = ThreadSafe(["a": 1], mechanism: mechanism)
    let popped = dictionary.popFirst()
    #expect(popped?.key == "a")
    #expect(popped?.value == 1)
    #expect(dictionary.isEmpty)

    let empty = ThreadSafe<[String: Int]>(mechanism: mechanism)
    #expect(empty.popFirst() == nil)
}

// Concurrent drains must remove every entry exactly once — no duplicates, no drops.
@Test(arguments: mechanisms) func threadSafeDictionaryConcurrentPopFirstDrainsExactlyOnce(mechanism: ThreadSafeMechanism) throws {
    let n = 2_000
    let dictionary = ThreadSafe(Dictionary(uniqueKeysWithValues: (0..<n).map { ($0, $0 * 2) }), mechanism: mechanism)
    let popped = ThreadSafe<[Int]>(mechanism: .lock)
    DispatchQueue.concurrentPerform(iterations: 8) { _ in
        while let (key, value) = dictionary.popFirst() {
            #expect(value == key * 2)
            popped.append(key)
        }
    }
    #expect(dictionary.isEmpty)
    #expect(popped.elements.count == n)
    #expect(Set(popped.elements) == Set(0..<n))
}

@Test(arguments: mechanisms) func threadSafeDictionaryReserveCapacity(mechanism: ThreadSafeMechanism) throws {
    let dictionary = ThreadSafe(["a": 1, "b": 2], mechanism: mechanism)
    dictionary.reserveCapacity(100)
    #expect(dictionary.dictionary == ["a": 1, "b": 2])
}

// Concurrent `reserveCapacity` must not drop concurrent writes.
@Test(arguments: mechanisms) func threadSafeDictionaryConcurrentReserveCapacityDoesNotCorruptConcurrentWrites(mechanism: ThreadSafeMechanism) throws {
    let dictionary = ThreadSafe<[Int: Int]>(mechanism: mechanism)
    let n = concurrencyIterations
    DispatchQueue.concurrentPerform(iterations: n * 2) { i in
        if i < n {
            dictionary[i] = i
        } else {
            dictionary.reserveCapacity(1_000)
        }
    }
    #expect(dictionary.count == n)
    #expect(dictionary.dictionary.allSatisfy { $0.value == $0.key })
}

@Test(arguments: mechanisms) func threadSafeDictionaryMergeSequenceOfPairs(mechanism: ThreadSafeMechanism) throws {
    let dictionary = ThreadSafe(["a": 1], mechanism: mechanism)
    dictionary.merge([("a", 2), ("b", 3)]) { _, new in new }
    #expect(dictionary.dictionary == ["a": 2, "b": 3])
}

// Disjoint key ranges, so this only checks for lost writes.
@Test(arguments: mechanisms) func threadSafeDictionaryConcurrentMergeSequenceOfPairsPreservesEveryEntry(mechanism: ThreadSafeMechanism) throws {
    let dictionary = ThreadSafe<[Int: Int]>(mechanism: mechanism)
    let writers = 8
    let perWriter = 250
    DispatchQueue.concurrentPerform(iterations: writers) { w in
        let pairs = (0..<perWriter).map { (w * perWriter + $0, w) }
        dictionary.merge(pairs) { _, new in new }
    }
    #expect(dictionary.count == writers * perWriter)
}

@Test(arguments: mechanisms) func threadSafeDictionaryFirstWhere(mechanism: ThreadSafeMechanism) throws {
    let dictionary = ThreadSafe(["a": 1, "b": 2], mechanism: mechanism)
    #expect(dictionary.first(where: { $0.value == 2 })?.key == "b")
    #expect(dictionary.first(where: { $0.value == 3 }) == nil)
}

@Test(arguments: mechanisms) func threadSafeDictionaryCountWhere(mechanism: ThreadSafeMechanism) throws {
    let dictionary = ThreadSafe(["a": 1, "b": 2, "c": 3], mechanism: mechanism)
    #expect(dictionary.count(where: { $0.value > 1 }) == 2)
}

@Test(arguments: mechanisms) func threadSafeDictionaryMinByAndMaxBy(mechanism: ThreadSafeMechanism) throws {
    let dictionary = ThreadSafe(["a": 3, "b": 1, "c": 2], mechanism: mechanism)
    #expect(dictionary.min(by: { $0.value < $1.value })?.key == "b")
    #expect(dictionary.max(by: { $0.value < $1.value })?.key == "a")
}

@Test(arguments: mechanisms) func threadSafeDictionaryReduceNonInto(mechanism: ThreadSafeMechanism) throws {
    let dictionary = ThreadSafe(["a": 1, "b": 2], mechanism: mechanism)
    let sum = dictionary.reduce(0) { $0 + $1.value }
    #expect(sum == 3)
}

@Test(arguments: mechanisms) func threadSafeDictionaryRandomElement(mechanism: ThreadSafeMechanism) throws {
    let dictionary = ThreadSafe(["a": 1, "b": 2], mechanism: mechanism)
    let element = dictionary.randomElement()
    #expect(element != nil)
    #expect(["a", "b"].contains(element!.key))

    let empty = ThreadSafe<[String: Int]>(mechanism: mechanism)
    #expect(empty.randomElement() == nil)
}

@Test(arguments: mechanisms) func threadSafeDictionaryAllSatisfy(mechanism: ThreadSafeMechanism) throws {
    let dictionary = ThreadSafe(["a": 2, "b": 4], mechanism: mechanism)
    #expect(dictionary.allSatisfy { $0.value % 2 == 0 })
    #expect(dictionary.allSatisfy { $0.value > 2 } == false)
}

@Test(arguments: mechanisms) func threadSafeDictionaryCompactMap(mechanism: ThreadSafeMechanism) throws {
    let dictionary = ThreadSafe(["a": 1, "b": 2], mechanism: mechanism)
    let values = dictionary.compactMap { $0.value == 1 ? nil : $0.value }
    #expect(values == [2])
}

@Test(arguments: mechanisms) func threadSafeDictionarySortedBy(mechanism: ThreadSafeMechanism) throws {
    let dictionary = ThreadSafe(["a": 3, "b": 1, "c": 2], mechanism: mechanism)
    let sorted = dictionary.sorted(by: { $0.value < $1.value })
    #expect(sorted.map(\.key) == ["b", "c", "a"])
}

