import Foundation
import Testing
@testable import ThreadSafeKit

@Test func dictionaryQueueSetAndGet() throws {
    let dictionary = DictionaryQueue<String, Int>()
    dictionary.setValue(42, forKey: "answer")
    #expect(dictionary.getValue(forKey: "answer") == 42)
    #expect(dictionary.count == 1)
}

@Test func dictionaryQueueInitWithDictionary() throws {
    let dictionary = DictionaryQueue(["a": 1, "b": 2])
    #expect(dictionary.count == 2)
    #expect(dictionary.getValue(forKey: "a") == 1)
}

@Test func dictionaryQueueIsEmptyAndDictionaryProperty() throws {
    let empty = DictionaryQueue<String, Int>()
    #expect(empty.isEmpty)

    let dictionary = DictionaryQueue(["a": 1])
    #expect(dictionary.isEmpty == false)
    #expect(dictionary.dictionary == ["a": 1])
}

@Test func dictionaryQueueRemoveValue() throws {
    let dictionary = DictionaryQueue(["a": 1])
    let removed = dictionary.removeValue(forKey: "a")
    #expect(removed == 1)
    #expect(dictionary.isEmpty)
}

@Test func dictionaryQueueRemoveAll() throws {
    let dictionary = DictionaryQueue(["a": 1, "b": 2])
    dictionary.removeAll()
    #expect(dictionary.isEmpty)
}

@Test func dictionaryQueueMerge() throws {
    let dictionary = DictionaryQueue(["a": 1])
    dictionary.merge(["a": 2, "b": 3]) { _, new in new }
    #expect(dictionary.dictionary == ["a": 2, "b": 3])
}

@Test func dictionaryQueueForEach() throws {
    let dictionary = DictionaryQueue(["a": 1, "b": 2])
    var sum = 0
    dictionary.forEach { sum += $0.value }
    #expect(sum == 3)
}

@Test func dictionaryQueueReduce() throws {
    let dictionary = DictionaryQueue(["a": 1, "b": 2])
    let sum = dictionary.reduce(into: 0) { result, entry in result += entry.value }
    #expect(sum == 3)
}

@Test func dictionaryQueueSubscript() throws {
    let dictionary = DictionaryQueue<String, Int>()
    dictionary["a"] = 1
    #expect(dictionary["a"] == 1)
}

@Test func dictionaryQueueSubscriptNilRemoves() throws {
    let dictionary = DictionaryQueue(["a": 1])
    dictionary["a"] = nil
    #expect(dictionary.isEmpty)
}

@Test func dictionaryQueueConcurrentSetsDoNotDropWrites() throws {
    let dictionary = DictionaryQueue<Int, Int>()
    DispatchQueue.concurrentPerform(iterations: concurrencyIterations) { i in
        dictionary.setValue(i, forKey: i)
    }
    #expect(dictionary.count == concurrencyIterations)
}

// Interleaves reads with writes to exercise the `.concurrent` + barrier
// design specifically: concurrent readers running alongside exclusive
// writers. A real race here is caught by Thread Sanitizer
// (`swift test --sanitize=thread`), not just by a dropped-write count.
@Test func dictionaryQueueConcurrentReadsDuringWritesDoNotRace() throws {
    let dictionary = DictionaryQueue<Int, Int>()
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

@Test func dictionaryQueueMutateReturnsValueAndMutates() throws {
    let dictionary = DictionaryQueue(["a": 1])
    let removed = dictionary.mutate { storage in
        storage["b"] = 2
        return storage.removeValue(forKey: "a")
    }
    #expect(removed == 1)
    #expect(dictionary.dictionary == ["b": 2])
}

// Each iteration reads the current counter value then writes back the increment
// (check-then-act). If `mutate` didn't hold the barrier lock for the whole closure,
// concurrent increments could race and lose updates.
@Test func dictionaryQueueMutateIsAtomicAcrossCompoundOperations() throws {
    let dictionary = DictionaryQueue<String, Int>()
    DispatchQueue.concurrentPerform(iterations: concurrencyIterations) { _ in
        dictionary.mutate { storage in
            storage["counter", default: 0] += 1
        }
    }
    #expect(dictionary.getValue(forKey: "counter") == concurrencyIterations)
}

// Demonstrates the exact problem `mutate` fixes: reading then setting as two
// separate queue syncs lets both reads observe the same stale value, losing
// an update. A single `mutate` call doesn't have this problem because both
// steps happen under one queue sync.
@Test func dictionaryQueueSeparateGetAndSetCanLoseUpdates() throws {
    let dictionary = DictionaryQueue<String, Int>()
    let a = dictionary.getValue(forKey: "counter") ?? 0
    let b = dictionary.getValue(forKey: "counter") ?? 0
    dictionary.setValue(a + 1, forKey: "counter")
    dictionary.setValue(b + 1, forKey: "counter")
    #expect(dictionary.getValue(forKey: "counter") == 1)
}

@Test func dictionaryQueueCodableRoundTrip() throws {
    let dictionary = DictionaryQueue(["a": 1, "b": 2])
    let data = try JSONEncoder().encode(dictionary)
    let decoded = try JSONDecoder().decode(DictionaryQueue<String, Int>.self, from: data)
    #expect(decoded.dictionary == ["a": 1, "b": 2])
}

// Auto-synthesized Codable on a containing type only compiles because
// DictionaryQueue<String, Int> conforms to Codable; this is the whole point of the feature.
@Test func dictionaryQueueCodableRoundTripInsideContainingType() throws {
    struct Container: Codable {
        let values: DictionaryQueue<String, Int>
    }
    let container = Container(values: DictionaryQueue(["a": 1]))
    let data = try JSONEncoder().encode(container)
    let decoded = try JSONDecoder().decode(Container.self, from: data)
    #expect(decoded.values.dictionary == ["a": 1])
}

@Test func dictionaryQueueEquatableComparesDictionary() throws {
    #expect(DictionaryQueue(["a": 1]) == DictionaryQueue(["a": 1]))
    #expect(DictionaryQueue(["a": 1]) != DictionaryQueue(["a": 2]))
    #expect(DictionaryQueue(["a": 1]) != DictionaryQueue(["a": 1, "b": 2]))
}

// Auto-synthesized Equatable on a containing type only compiles because
// DictionaryQueue<String, Int> conforms to Equatable; this is the whole point of the feature.
@Test func dictionaryQueueEquatableInsideContainingType() throws {
    struct Container: Equatable {
        let values: DictionaryQueue<String, Int>
    }
    #expect(Container(values: DictionaryQueue(["a": 1])) == Container(values: DictionaryQueue(["a": 1])))
    #expect(Container(values: DictionaryQueue(["a": 1])) != Container(values: DictionaryQueue(["a": 2])))
}

@Test func dictionaryQueueHashableUsableInSet() throws {
    let set: Set<DictionaryQueue<String, Int>> = [DictionaryQueue(["a": 1]), DictionaryQueue(["a": 1]), DictionaryQueue(["a": 2])]
    #expect(set.count == 2)
}

// Hash must not depend on insertion/iteration order, since Dictionary itself has no
// Hashable conformance and the implementation combines entries independently.
@Test func dictionaryQueueHashIsOrderIndependent() throws {
    var a = Hasher()
    DictionaryQueue(["a": 1, "b": 2]).hash(into: &a)
    var b = Hasher()
    DictionaryQueue(["b": 2, "a": 1]).hash(into: &b)
    #expect(a.finalize() == b.finalize())
}
