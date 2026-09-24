import Foundation
import Testing
@testable import ThreadSafeKit

private let mechanisms: [ThreadSafeMechanism] = [.lock, .dispatchQueue]

@Test(arguments: mechanisms) func threadSafeDictionarySetAndGet(mechanism: ThreadSafeMechanism) throws {
    let dictionary = ThreadSafe<[String: Int]>(mechanism: mechanism)
    dictionary.setValue(42, forKey: "answer")
    #expect(dictionary.getValue(forKey: "answer") == 42)
    #expect(dictionary.count == 1)
}

@Test(arguments: mechanisms) func threadSafeDictionaryInitWithDictionary(mechanism: ThreadSafeMechanism) throws {
    let dictionary = ThreadSafe(["a": 1, "b": 2], mechanism: mechanism)
    #expect(dictionary.count == 2)
    #expect(dictionary.getValue(forKey: "a") == 1)
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
        dictionary.setValue(i, forKey: i)
    }
    #expect(dictionary.count == concurrencyIterations)
}

// Interleaves reads with writes to exercise the backing mechanism specifically: whether it's the
// unfair lock (all access exclusive) or the concurrent queue + barrier (concurrent readers, exclusive
// writers), concurrent readers and writers still can't race. A real race here is caught by Thread
// Sanitizer (`swift test --sanitize=thread`), not just by a dropped-write count.
@Test(arguments: mechanisms) func threadSafeDictionaryConcurrentReadsDuringWritesDoNotRace(mechanism: ThreadSafeMechanism) throws {
    let dictionary = ThreadSafe<[Int: Int]>(mechanism: mechanism)
    DispatchQueue.concurrentPerform(iterations: concurrencyIterations * 2) { i in
        if i % 2 == 0 {
            dictionary.setValue(i, forKey: i)
        } else {
            _ = dictionary.count
            _ = dictionary.dictionary
            _ = dictionary.getValue(forKey: 0)
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
    #expect(dictionary.getValue(forKey: "counter") == concurrencyIterations)
}

// Demonstrates the exact problem `mutate` fixes: reading then setting as two
// separate lock/queue acquisitions lets both reads observe the same stale value, losing
// an update. A single `mutate` call doesn't have this problem because both
// steps happen under one acquisition.
@Test(arguments: mechanisms) func threadSafeDictionarySeparateGetAndSetCanLoseUpdates(mechanism: ThreadSafeMechanism) throws {
    let dictionary = ThreadSafe<[String: Int]>(mechanism: mechanism)
    let a = dictionary.getValue(forKey: "counter") ?? 0
    let b = dictionary.getValue(forKey: "counter") ?? 0
    dictionary.setValue(a + 1, forKey: "counter")
    dictionary.setValue(b + 1, forKey: "counter")
    #expect(dictionary.getValue(forKey: "counter") == 1)
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
    $values.setValue(2, forKey: "b")
    #expect(values == ["a": 1, "b": 2])
    #expect($values.count == 2)
}

