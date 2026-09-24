/// Backing mechanism for ``ThreadSafe``, the lock-based thread-safe wrapper. The actor-backed
/// alternatives (``ThreadSafeArray``, ``ThreadSafeDictionary``, ``ThreadSafeSet``, ``ThreadSafeAtomic``) don't take this —
/// actor isolation always requires `await`, so there's no sync/mechanism choice to make.
///
/// Per-call costs from `ThreadSafeKitBenchmarks` (Apple M4 Max, release build; real numbers vary
/// by machine and load, so treat these as a comparison between mechanisms, not a contract).
/// Contended rows are 8 threads sharing one instance. Full results: `Benchmarks/RESULTS.md`.
///
/// | Workload | `.lock` | `.readerWriterLock` |
/// |---|---|---|
/// | `count` | ~5ns | ~20ns |
/// | `a[i] += 1` | ~12ns | ~27ns |
/// | Contended short reads (`a[i]`) | ~47ns | ~340ns |
/// | Contended short reads, 10% writes | ~49ns | ~1,320ns |
/// | Contended scan (`count(where:)`), 64 elements | ~146ns | ~378ns |
/// | Contended scan, 256 elements | ~381ns | ~367ns |
/// | Contended scan, 1k elements | ~1,100ns | ~308ns |
/// | Contended scan, 10k elements | ~9,236ns | ~1,043ns |
/// | Contended 10k scan, 50% writes | ~7,322ns | ~3,728ns |
///
/// Use `.lock` (the default) unless many threads read the same instance at once and each read
/// walks a large part of it (`filter`, `map`, `sorted`, `contains(where:)`, ... over roughly 1,000+
/// elements). Only then do parallel readers pay for `.readerWriterLock`'s higher per-call cost: it
/// breaks even around 256 elements and is several times faster from 1,000 up, even with half the
/// operations being writes. For short operations it's 1.5–30× slower, because it pays for
/// ``ReentrancyTracker`` (`pthread_rwlock` would hang on some reentrant combinations instead of
/// trapping) and for reader bookkeeping.
///
/// `os_unfair_lock` records its owner so the system can attempt to resolve priority inversions
/// (`os/lock.h`); `pthread_rwlock` offers no priority-inheritance option.
public enum ThreadSafeMechanism: Sendable {
    /// `pthread_rwlock_t`, locked manually: concurrent reads, exclusive writes. For many threads
    /// reading a large collection at once (see the table above). Same-thread reentry traps with
    /// this package's own message, via ``ReentrancyTracker``.
    case readerWriterLock
    /// `OSAllocatedUnfairLock`. **Default.** Every access, reads included, is exclusive. Faster than
    /// `.readerWriterLock` for everything except concurrent reads over large collections (see the
    /// table above). The trade-off: same-thread
    /// reentry crashes with `os_unfair_lock`'s own message ("BUG IN CLIENT OF LIBPLATFORM: Trying to
    /// recursively lock an os_unfair_lock", in the crash report) rather than this package's own.
    case lock
}
