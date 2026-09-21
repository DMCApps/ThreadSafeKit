import Foundation
import Testing
@testable import ThreadSafeKit

@Test func atomicActorMutates() async throws {
    let counter = AtomicActor(0)
    await counter.mutate { $0 += 1 }
    #expect(await counter.get() == 1)
}

@Test func atomicActorSetAndGet() async throws {
    let value = AtomicActor(1)
    await value.set(2)
    #expect(await value.get() == 2)
}

@Test func atomicActorConcurrentMutationsDoNotDropWrites() async throws {
    let counter = AtomicActor(0)
    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<concurrencyIterations {
            group.addTask { await counter.mutate { $0 += 1 } }
        }
    }
    #expect(await counter.get() == concurrencyIterations)
}
