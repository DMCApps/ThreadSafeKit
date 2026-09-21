import Foundation
import Testing
@testable import ThreadSafeKit

@Test func arrayQueueAppendAndRead() throws {
    let array = ArrayQueue<Int>()
    array.append(1)
    array.append(2)
    #expect(array.count == 2)
    #expect(array[0] == 1)
    #expect(array.pop() == 2)
}

@Test func arrayQueueInitWithSequence() throws {
    let array = ArrayQueue([1, 2, 3])
    #expect(array.elements == [1, 2, 3])
}

@Test func arrayQueueIsEmptyFirstLast() throws {
    let empty = ArrayQueue<Int>()
    #expect(empty.isEmpty)
    #expect(empty.first == nil)
    #expect(empty.last == nil)

    let array = ArrayQueue([1, 2, 3])
    #expect(array.isEmpty == false)
    #expect(array.first == 1)
    #expect(array.last == 3)
}

@Test func arrayQueuePush() throws {
    let array = ArrayQueue([2, 3])
    array.push(1)
    #expect(array.elements == [1, 2, 3])
}

@Test func arrayQueueRemoveAt() throws {
    let array = ArrayQueue([1, 2, 3])
    let removed = array.remove(at: 1)
    #expect(removed == 2)
    #expect(array.elements == [1, 3])
}

@Test func arrayQueueRemoveAll() throws {
    let array = ArrayQueue([1, 2, 3])
    array.removeAll()
    #expect(array.isEmpty)
}

@Test func arrayQueueForEach() throws {
    let array = ArrayQueue([1, 2, 3])
    var sum = 0
    array.forEach { sum += $0 }
    #expect(sum == 6)
}

@Test func arrayQueueMap() throws {
    let array = ArrayQueue([1, 2, 3])
    let doubled = array.map { $0 * 2 }
    #expect(doubled == [2, 4, 6])
}

@Test func arrayQueueSubscriptSafe() throws {
    let array = ArrayQueue([1, 2, 3])
    #expect(array[safe: 0] == 1)
    #expect(array[safe: 3] == nil)
}

@Test func arrayQueueSubscriptSet() throws {
    let array = ArrayQueue([1, 2, 3])
    array[1] = 20
    #expect(array.elements == [1, 20, 3])
}

@Test func arrayQueueConcurrentAppendsDoNotDropWrites() throws {
    let array = ArrayQueue<Int>()
    DispatchQueue.concurrentPerform(iterations: concurrencyIterations) { i in
        array.append(i)
    }
    #expect(array.count == concurrencyIterations)
}

// Interleaves reads with writes to exercise the `.concurrent` + barrier
// design specifically: concurrent readers running alongside exclusive
// writers. A real race here is caught by Thread Sanitizer
// (`swift test --sanitize=thread`), not just by a dropped-write count.
@Test func arrayQueueConcurrentReadsDuringWritesDoNotRace() throws {
    let array = ArrayQueue<Int>()
    DispatchQueue.concurrentPerform(iterations: concurrencyIterations * 2) { i in
        if i % 2 == 0 {
            array.append(i)
        } else {
            _ = array.count
            _ = array.elements
            _ = array.first
            _ = array.last
            _ = array[safe: 0]
        }
    }
    #expect(array.count == concurrencyIterations)
}
