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
