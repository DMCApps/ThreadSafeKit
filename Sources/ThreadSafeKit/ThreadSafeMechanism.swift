/// Lock backing ``ThreadSafe``; use `.lock` unless many threads concurrently scan ~1,000+ elements (see `Benchmarks/RESULTS.md`).
public enum ThreadSafeMechanism: Sendable {
    /// `pthread_rwlock_t` allowing concurrent reads; reentry traps via ``ReentrancyTracker``.
    case readerWriterLock
    /// `OSAllocatedUnfairLock`, fully exclusive and fastest for short operations (default).
    case lock
}
