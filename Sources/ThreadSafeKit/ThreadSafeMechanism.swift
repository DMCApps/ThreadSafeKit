/// Backing mechanism for ``ThreadSafe``, the lock/queue-based thread-safe wrapper. The actor-backed
/// alternatives (``ThreadSafeArray``, ``ThreadSafeDictionary``, ``ThreadSafeAtomic``) don't take this —
/// actor isolation always requires `await`, so there's no sync/mechanism choice to make.
///
/// Approximate, uncontended, per-call costs (Apple silicon, release build; real numbers vary by
/// machine/load — these are for relative comparison between mechanisms, not a performance
/// contract):
///
/// | Mechanism | `get` | `set`/`+=`/`?.append` |
/// |---|---|---|
/// | `.lock` | ~75-180ns | ~90-180ns |
/// | `.readerWriterLock` | ~75-110ns | ~85-110ns |
/// | `.dispatchQueue` | ~250-290ns | ~13,000-38,000ns |
///
/// `.readerWriterLock` and `.lock` are the same cost tier — `.readerWriterLock` additionally
/// allows concurrent reads, for effectively no extra cost, which is why it's the default.
/// `.dispatchQueue`'s subscript writes are ~100-400x more expensive than the other two: a
/// subscript's in-place modify can't `yield` from inside `DispatchQueue.sync`, so it has to spawn
/// a dedicated OS thread to hold the barrier queue open instead (see `beginModify()` in
/// ThreadSafe.swift) — real thread creation, not a lock, is what costs the microseconds.
public enum ThreadSafeMechanism: Sendable {
    /// `pthread_rwlock_t`, locked manually: concurrent reads, exclusive writes. **Default.** Same
    /// cost tier as `.lock` (~75-110ns/call) but allows concurrent reads on top of that, and a
    /// subscript's in-place modify holds the write lock directly across its `yield` (no queue to
    /// park, so no extra cost for compound edits like `.dispatchQueue` has). The strongest general
    /// default: pick something else only for a specific reason below.
    case readerWriterLock
    /// `OSAllocatedUnfairLock`. ~75-180ns/call. Every access — reads included — is fully
    /// exclusive; there's no concurrent-reads case to make here. Prefer this over
    /// `.readerWriterLock` only for write-dominated workloads with no meaningful read concurrency
    /// to exploit, where `pthread_rwlock`'s reader/writer fairness bookkeeping is pure overhead
    /// over `os_unfair_lock`'s simpler implementation (not independently measured here — a
    /// hypothesis about write-heavy contention, not a confirmed number).
    case lock
    /// `DispatchQueue`, concurrent with barrier writes: reads run in parallel, writes are
    /// exclusive — the same semantics as `.readerWriterLock`, at a real cost premium (~250-290ns
    /// for `get`, since `dispatch_sync` is inherently heavier machinery than a raw lock even
    /// uncontended). A subscript's in-place modify (`ts[i] += 1`, `ts[i]?.append(x)`, plain
    /// `ts[i] = v`) "parks" the queue for the duration by spawning a dedicated thread instead of
    /// running inside a `sync` call — measured at ~13,000-38,000ns per compound edit, and it
    /// blocks a GCD worker thread for that whole window, which can stall other low-QoS work
    /// queued behind it. Kept only for source/behavior compatibility with code written against
    /// this as the previous default; prefer `.readerWriterLock` for new code.
    case dispatchQueue
}
