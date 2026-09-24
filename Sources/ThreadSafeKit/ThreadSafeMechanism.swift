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
///
/// `.readerWriterLock` and `.lock` are the same cost tier — `.readerWriterLock` additionally
/// allows concurrent reads, for effectively no extra cost, which is why it's the default.
public enum ThreadSafeMechanism: Sendable {
    /// `pthread_rwlock_t`, locked manually: concurrent reads, exclusive writes. **Default.** Same
    /// cost tier as `.lock` (~75-110ns/call) but allows concurrent reads on top of that, and a
    /// subscript's in-place modify holds the write lock directly across its `yield` (no queue to
    /// park, so no extra cost for compound edits). The strongest general default: pick `.lock`
    /// only for a specific reason below.
    case readerWriterLock
    /// `OSAllocatedUnfairLock`. ~75-180ns/call. Every access — reads included — is fully
    /// exclusive; there's no concurrent-reads case to make here. Prefer this over
    /// `.readerWriterLock` only for write-dominated workloads with no meaningful read concurrency
    /// to exploit, where `pthread_rwlock`'s reader/writer fairness bookkeeping is pure overhead
    /// over `os_unfair_lock`'s simpler implementation (not independently measured here — a
    /// hypothesis about write-heavy contention, not a confirmed number).
    case lock
}
