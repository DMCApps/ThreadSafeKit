import Testing

@testable import ThreadSafeKit

// Absolute-time ceilings for every callable `ThreadSafeAtomic` member.

@Test(.tags(.performance))
func atomicActorGetIsFast() async {
    let atomic = ThreadSafeAtomic(0)
    await assertFast("get") { _ = await atomic.get() }
}

@Test(.tags(.performance))
func atomicActorMutateIsFast() async {
    let atomic = ThreadSafeAtomic(0)
    await assertFast("mutate") { await atomic.mutate { $0 += 1 } }
}
