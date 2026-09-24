/// Backing mechanism for ``ThreadSafe``, the lock-based thread-safe wrapper. The actor-backed
/// alternatives (``ThreadSafeArray``, ``ThreadSafeDictionary``, ``ThreadSafeAtomic``) don't take this —
/// actor isolation always requires `await`, so there's no sync/mechanism choice to make.
///
/// Approximate, uncontended, single-thread, per-call costs (Apple silicon, release build; real
/// numbers vary by machine/load — these are for relative comparison between mechanisms, not a
/// performance contract):
///
/// | Mechanism | `get` (`count`) | `set`/`+=` (`a[i] += 1`) | `append`+`pop` |
/// |---|---|---|---|
/// | `.lock` | ~4ns | ~12ns | ~19ns |
/// | `.readerWriterLock` | ~20ns | ~28ns | ~49ns |
///
/// `.lock` is now the cheaper of the two: it skips ``ReentrancyTracker`` entirely (`os_unfair_lock`
/// already traps on a same-thread relock, so tracking would be pure overhead), landing within a
/// few ns of a bare `OSAllocatedUnfairLock` lock/unlock. `.readerWriterLock` still needs the
/// tracker — `pthread_rwlock` read-in-read succeeds and only deadlocks once a writer queues, so
/// without tracking that case would hang instead of trap — which is why it costs more per call
/// despite a bare `pthread_rwlock` rdlock/unlock being *cheaper* than a bare unfair lock/unlock.
/// `.readerWriterLock` remains the default: the numbers above are all uncontended single-thread
/// costs, and its concurrent-reads advantage only shows up under real read contention, which this
/// table doesn't measure.
public enum ThreadSafeMechanism: Sendable {
    /// `pthread_rwlock_t`, locked manually: concurrent reads, exclusive writes. **Default.** Pick
    /// `.lock` instead only for a specific reason below — `.readerWriterLock`'s extra per-call
    /// cost buys concurrent reads, and a subscript's in-place modify holds the write lock directly
    /// across its `yield` (no queue to park, so no extra cost for compound edits).
    case readerWriterLock
    /// `OSAllocatedUnfairLock`. Every access — reads included — is fully exclusive; there's no
    /// concurrent-reads case to make here. Cheaper per call than `.readerWriterLock` (see the
    /// table above) because it needs no reentrancy tracker, so prefer it for write-dominated
    /// workloads with no meaningful read concurrency to exploit, where `.readerWriterLock`'s
    /// reader/writer bookkeeping would be pure overhead. The trade-off: same-thread reentry
    /// crashes with `os_unfair_lock`'s own message ("Trying to recursively lock an
    /// os_unfair_lock...") rather than this package's own reentrancy-trap message.
    case lock
}
