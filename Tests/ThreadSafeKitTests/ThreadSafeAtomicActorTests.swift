import Foundation
import Testing
@testable import ThreadSafeKit

@Test func atomicActorMutates() async throws {
    let counter = ThreadSafeAtomic(0)
    await counter.mutate { $0 += 1 }
    #expect(await counter.get() == 1)
}

@Test func atomicActorMutateAndGet() async throws {
    let value = ThreadSafeAtomic(1)
    await value.mutate { $0 = 2 }
    #expect(await value.get() == 2)
}

@Test func atomicActorMutateReturnsValueAndMutates() async throws {
    let counter = ThreadSafeAtomic(5)
    let old = await counter.mutate { v in
        defer { v += 1 }
        return v
    }
    #expect(old == 5)
    #expect(await counter.get() == 6)
}

// Concurrent ID allocation via `mutate` must yield exactly 0..<1000.
@Test func atomicActorConcurrentMutateReturningValueHandsOutUniqueSequentialIDs() async throws {
    let idGenerator = ThreadSafeAtomic(0)
    let ids = await withTaskGroup(of: Int.self, returning: [Int].self) { group in
        for _ in 0..<1_000 {
            group.addTask {
                await idGenerator.mutate { value in
                    defer { value += 1 }
                    return value
                }
            }
        }
        return await group.reduce(into: []) { $0.append($1) }
    }
    #expect(Set(ids) == Set(0..<1_000))
    #expect(ids.count == 1_000)
}

private struct AtomicMutateBoom: Error {}

// The error propagates and the pre-throw mutation is kept; `mutate` isn't transactional.
@Test func atomicActorMutateThrowsPropagatesErrorAndKeepsPartialMutation() async throws {
    let counter = ThreadSafeAtomic(0)
    await #expect(throws: AtomicMutateBoom.self) {
        try await counter.mutate { value -> Void in
            value = 1
            throw AtomicMutateBoom()
        }
    }
    #expect(await counter.get() == 1)
}

@Test func atomicActorConcurrentMutationsDoNotDropWrites() async throws {
    let counter = ThreadSafeAtomic(0)
    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<concurrencyIterations {
            group.addTask { await counter.mutate { $0 += 1 } }
        }
    }
    #expect(await counter.get() == concurrencyIterations)
}
