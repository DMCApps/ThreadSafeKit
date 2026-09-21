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
