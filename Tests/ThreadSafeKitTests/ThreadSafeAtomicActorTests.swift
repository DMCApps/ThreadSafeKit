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

@Test func atomicActorConcurrentMutationsDoNotDropWrites() async throws {
    let counter = ThreadSafeAtomic(0)
    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<concurrencyIterations {
            group.addTask { await counter.mutate { $0 += 1 } }
        }
    }
    #expect(await counter.get() == concurrencyIterations)
}

// Demonstrates the exact problem `mutate` fixes: reading and writing as two
// separate actor calls lets a stale read clobber a concurrent write, even
// though each individual call is itself atomic. A single `mutate` call doesn't
// have this problem because both steps happen under one actor call.
@Test func atomicActorSeparateGetAndMutateCanLoseUpdates() async throws {
    let counter = ThreadSafeAtomic(0)
    let a = await counter.get()
    let b = await counter.get()
    await counter.mutate { $0 = a + 1 }
    await counter.mutate { $0 = b + 1 }
    #expect(await counter.get() == 1)
}
