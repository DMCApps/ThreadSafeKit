/// Backing mechanism for ``ThreadSafe``, the lock-based thread-safe wrapper. The actor-backed
/// alternatives (``ThreadSafeArray``, ``ThreadSafeDictionary``, ``ThreadSafeSet``, ``ThreadSafeAtomic``) don't take this —
/// actor isolation always requires `await`, so there's no sync/mechanism choice to make.
///
/// Per-call costs from `ThreadSafeKitBenchmarks` (Apple M4 Max, release build; real numbers vary
/// by machine and load, so treat these as a comparison between mechanisms, not a contract). The
/// contended rows are 8 threads sharing one instance. Full results: `Benchmarks/RESULTS.md`.
///
/// | Mechanism | `count` | `a[i] += 1` | `append` + `popLast` | Contended 100% read | Contended 100% write |
/// |---|---|---|---|---|---|
/// | `.lock` | ~4ns | ~12ns | ~19ns | ~45ns | ~74ns |
/// | `.readerWriterLock` | ~20ns | ~27ns | ~52ns | ~340ns | ~2260ns |
///
/// `.lock` is cheaper in every measured row, including contended reads. It skips
/// ``ReentrancyTracker`` entirely, because `os_unfair_lock` already traps on a same-thread relock.
/// `.readerWriterLock` needs the tracker (`pthread_rwlock` would hang on some reentrant
/// combinations instead of trapping), which adds per-call cost. The benchmark's critical sections
/// are short; reads that hold the lock for a long time (e.g. `filter` over a large collection)
/// aren't measured.
public enum ThreadSafeMechanism: Sendable {
    /// `pthread_rwlock_t`, locked manually: concurrent reads, exclusive writes. **Default.**
    /// Same-thread reentry traps with this package's own message, via ``ReentrancyTracker``.
    case readerWriterLock
    /// `OSAllocatedUnfairLock`. Every access, reads included, is exclusive. Cheaper than
    /// `.readerWriterLock` in every measured row (see the table above). The trade-off: same-thread
    /// reentry crashes with `os_unfair_lock`'s own message ("BUG IN CLIENT OF LIBPLATFORM: Trying to
    /// recursively lock an os_unfair_lock", in the crash report) rather than this package's own.
    case lock
}
