import Foundation
import Testing
@testable import ThreadSafeKit

@Test func dictionaryLockSetAndGet() throws {
    let dictionary = DictionaryLock<String, Int>()
    dictionary.setValue(42, forKey: "answer")
    #expect(dictionary.getValue(forKey: "answer") == 42)
    #expect(dictionary.count == 1)
}

@Test func dictionaryLockInitWithDictionary() throws {
    let dictionary = DictionaryLock(["a": 1, "b": 2])
    #expect(dictionary.count == 2)
    #expect(dictionary.getValue(forKey: "a") == 1)
}

@Test func dictionaryLockIsEmptyAndDictionaryProperty() throws {
    let empty = DictionaryLock<String, Int>()
    #expect(empty.isEmpty)

    let dictionary = DictionaryLock(["a": 1])
    #expect(dictionary.isEmpty == false)
    #expect(dictionary.dictionary == ["a": 1])
}

@Test func dictionaryLockRemoveValue() throws {
    let dictionary = DictionaryLock(["a": 1])
    let removed = dictionary.removeValue(forKey: "a")
    #expect(removed == 1)
    #expect(dictionary.isEmpty)
}

@Test func dictionaryLockRemoveAll() throws {
    let dictionary = DictionaryLock(["a": 1, "b": 2])
    dictionary.removeAll()
    #expect(dictionary.isEmpty)
}

@Test func dictionaryLockMerge() throws {
    let dictionary = DictionaryLock(["a": 1])
    dictionary.merge(["a": 2, "b": 3]) { _, new in new }
    #expect(dictionary.dictionary == ["a": 2, "b": 3])
}

@Test func dictionaryLockForEach() throws {
    let dictionary = DictionaryLock(["a": 1, "b": 2])
    let sum = Atomic(wrappedValue: 0)
    dictionary.forEach { entry in sum.mutate { $0 += entry.value } }
    #expect(sum.wrappedValue == 3)
}

@Test func dictionaryLockReduce() throws {
    let dictionary = DictionaryLock(["a": 1, "b": 2])
    let sum = dictionary.reduce(into: 0) { result, entry in result += entry.value }
    #expect(sum == 3)
}

@Test func dictionaryLockSubscript() throws {
    let dictionary = DictionaryLock<String, Int>()
    dictionary["a"] = 1
    #expect(dictionary["a"] == 1)
}

@Test func dictionaryLockSubscriptNilRemoves() throws {
    let dictionary = DictionaryLock(["a": 1])
    dictionary["a"] = nil
    #expect(dictionary.isEmpty)
}

@Test func dictionaryLockConcurrentSetsDoNotDropWrites() throws {
    let dictionary = DictionaryLock<Int, Int>()
    DispatchQueue.concurrentPerform(iterations: concurrencyIterations) { i in
        dictionary.setValue(i, forKey: i)
    }
    #expect(dictionary.count == concurrencyIterations)
}

// Interleaves reads with writes to exercise the lock specifically: all access
// is exclusive, so concurrent readers and writers still can't race. A real
// race here is caught by Thread Sanitizer (`swift test --sanitize=thread`),
// not just by a dropped-write count.
@Test func dictionaryLockConcurrentReadsDuringWritesDoNotRace() throws {
    let dictionary = DictionaryLock<Int, Int>()
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

@Test func dictionaryLockMutateReturnsValueAndMutates() throws {
    let dictionary = DictionaryLock(["a": 1])
    let removed = dictionary.mutate { storage in
        storage["b"] = 2
        return storage.removeValue(forKey: "a")
    }
    #expect(removed == 1)
    #expect(dictionary.dictionary == ["b": 2])
}

// Each iteration reads the current counter value then writes back the increment
// (check-then-act). If `mutate` didn't hold the lock for the whole closure,
// concurrent increments could race and lose updates.
@Test func dictionaryLockMutateIsAtomicAcrossCompoundOperations() throws {
    let dictionary = DictionaryLock<String, Int>()
    DispatchQueue.concurrentPerform(iterations: concurrencyIterations) { _ in
        dictionary.mutate { storage in
            storage["counter", default: 0] += 1
        }
    }
    #expect(dictionary.getValue(forKey: "counter") == concurrencyIterations)
}

// Demonstrates the exact problem `mutate` fixes: reading then setting as two
// separate lock acquisitions lets both reads observe the same stale value, losing
// an update. A single `mutate` call doesn't have this problem because both
// steps happen under one lock acquisition.
@Test func dictionaryLockSeparateGetAndSetCanLoseUpdates() throws {
    let dictionary = DictionaryLock<String, Int>()
    let a = dictionary.getValue(forKey: "counter") ?? 0
    let b = dictionary.getValue(forKey: "counter") ?? 0
    dictionary.setValue(a + 1, forKey: "counter")
    dictionary.setValue(b + 1, forKey: "counter")
    #expect(dictionary.getValue(forKey: "counter") == 1)
}

@Test func dictionaryLockCodableRoundTrip() throws {
    let dictionary = DictionaryLock(["a": 1, "b": 2])
    let data = try JSONEncoder().encode(dictionary)
    let decoded = try JSONDecoder().decode(DictionaryLock<String, Int>.self, from: data)
    #expect(decoded.dictionary == ["a": 1, "b": 2])
}

// Auto-synthesized Codable on a containing type only compiles because
// DictionaryLock<String, Int> conforms to Codable; this is the whole point of the feature.
@Test func dictionaryLockCodableRoundTripInsideContainingType() throws {
    struct Container: Codable {
        let values: DictionaryLock<String, Int>
    }
    let container = Container(values: DictionaryLock(["a": 1]))
    let data = try JSONEncoder().encode(container)
    let decoded = try JSONDecoder().decode(Container.self, from: data)
    #expect(decoded.values.dictionary == ["a": 1])
}

@Test func dictionaryLockEquatableComparesDictionary() throws {
    #expect(DictionaryLock(["a": 1]) == DictionaryLock(["a": 1]))
    #expect(DictionaryLock(["a": 1]) != DictionaryLock(["a": 2]))
    #expect(DictionaryLock(["a": 1]) != DictionaryLock(["a": 1, "b": 2]))
}

// Auto-synthesized Equatable on a containing type only compiles because
// DictionaryLock<String, Int> conforms to Equatable; this is the whole point of the feature.
@Test func dictionaryLockEquatableInsideContainingType() throws {
    struct Container: Equatable {
        let values: DictionaryLock<String, Int>
    }
    #expect(Container(values: DictionaryLock(["a": 1])) == Container(values: DictionaryLock(["a": 1])))
    #expect(Container(values: DictionaryLock(["a": 1])) != Container(values: DictionaryLock(["a": 2])))
}
