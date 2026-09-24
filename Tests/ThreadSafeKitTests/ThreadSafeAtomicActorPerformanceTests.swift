import Testing

@testable import ThreadSafeKit

// Performance coverage for `ThreadSafeAtomic`: every callable public member stays within a
// generous absolute-time ceiling for an actor hop (see `assertFast`'s async overload in
// TestSupport.swift). `set(_:)` is `@available(*, unavailable)` and so isn't callable here.

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
