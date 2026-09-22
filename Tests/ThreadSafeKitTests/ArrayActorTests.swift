import Foundation
import Testing
@testable import ThreadSafeKit

@Test func arrayActorAppendAndRead() async throws {
    let array = ArrayActor<Int>()
    await array.append(1)
    await array.append(2)
    #expect(await array.count == 2)
    #expect(await array[0] == 1)
    #expect(await array.pop() == 2)
}

@Test func arrayActorInitWithSequence() async throws {
    let array = ArrayActor([1, 2, 3])
    #expect(await array.elements == [1, 2, 3])
}

@Test func arrayActorIsEmptyFirstLast() async throws {
    let empty = ArrayActor<Int>()
    #expect(await empty.isEmpty)
    #expect(await empty.first == nil)
    #expect(await empty.last == nil)

    let array = ArrayActor([1, 2, 3])
    #expect(await array.isEmpty == false)
    #expect(await array.first == 1)
    #expect(await array.last == 3)
}

@Test func arrayActorPush() async throws {
    let array = ArrayActor([2, 3])
    await array.push(1)
    #expect(await array.elements == [1, 2, 3])
}

@Test func arrayActorRemoveAt() async throws {
    let array = ArrayActor([1, 2, 3])
    let removed = await array.remove(at: 1)
    #expect(removed == 2)
    #expect(await array.elements == [1, 3])
}

@Test func arrayActorRemoveAll() async throws {
    let array = ArrayActor([1, 2, 3])
    await array.removeAll()
    #expect(await array.isEmpty)
}

@Test func arrayActorForEach() async throws {
    let array = ArrayActor([1, 2, 3])
    let sum = Atomic(wrappedValue: 0)
    await array.forEach { element in sum.mutate { $0 += element } }
    #expect(sum.wrappedValue == 6)
}

@Test func arrayActorMap() async throws {
    let array = ArrayActor([1, 2, 3])
    let doubled = await array.map { $0 * 2 }
    #expect(doubled == [2, 4, 6])
}

@Test func arrayActorSubscriptSafe() async throws {
    let array = ArrayActor([1, 2, 3])
    #expect(await array[safe: 0] == 1)
    #expect(await array[safe: 3] == nil)
}

@Test func arrayActorSetElement() async throws {
    let array = ArrayActor([1, 2, 3])
    await array.setElement(20, at: 1)
    #expect(await array.elements == [1, 20, 3])
}

@Test func arrayActorConcurrentAppendsDoNotDropWrites() async throws {
    let array = ArrayActor<Int>()
    await withTaskGroup(of: Void.self) { group in
        for i in 0..<concurrencyIterations {
            group.addTask { await array.append(i) }
        }
    }
    #expect(await array.count == concurrencyIterations)
}

// Interleaves reads with writes (not just writes vs writes), proving mixed
// operations don't deadlock or corrupt state under actor reentrancy. A real
// race here is caught by Thread Sanitizer (`swift test --sanitize=thread`),
// not just by a dropped-write count.
@Test func arrayActorConcurrentReadsDuringWritesDoNotRace() async throws {
    let array = ArrayActor<Int>()
    await withTaskGroup(of: Void.self) { group in
        for i in 0..<(concurrencyIterations * 2) {
            group.addTask {
                if i % 2 == 0 {
                    await array.append(i)
                } else {
                    _ = await array.count
                    _ = await array.elements
                    _ = await array.first
                    _ = await array.last
                    _ = await array[safe: 0]
                }
            }
        }
    }
    #expect(await array.count == concurrencyIterations)
}

@Test func arrayActorMutateReturnsValueAndMutates() async throws {
    let array = ArrayActor([1, 2, 3])
    let sum = await array.mutate { elements in
        let total = elements.reduce(0, +)
        elements.append(total)
        return total
    }
    #expect(sum == 6)
    #expect(await array.elements == [1, 2, 3, 6])
}

// Each task reads the current count then appends it (check-then-act). If `mutate`
// didn't hold the actor for the whole closure, two tasks could read the same count
// and append duplicate values, leaving gaps/dupes instead of a clean permutation of 0..<N.
@Test func arrayActorMutateIsAtomicAcrossCompoundOperations() async throws {
    let array = ArrayActor<Int>()
    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<concurrencyIterations {
            group.addTask {
                await array.mutate { elements in
                    elements.append(elements.count)
                }
            }
        }
    }
    #expect(await array.elements.sorted() == Array(0..<concurrencyIterations))
}

// Demonstrates the exact problem `mutate` fixes: reading `count` then appending
// as two separate actor calls lets both reads observe the same stale count,
// producing a duplicate instead of a clean sequence. A single `mutate` call
// doesn't have this problem because both steps happen under one actor call.
@Test func arrayActorSeparateCountAndAppendCanProduceDuplicates() async throws {
    let array = ArrayActor<Int>()
    let countA = await array.count
    let countB = await array.count
    await array.append(countA)
    await array.append(countB)
    #expect(await array.elements == [0, 0])
}
