/// Backing mechanism for ``ThreadSafe``, the lock/queue-based thread-safe wrapper. The actor-backed
/// alternatives (``ThreadSafeArray``, ``ThreadSafeDictionary``, ``ThreadSafeAtomic``) don't take this —
/// actor isolation always requires `await`, so there's no sync/mechanism choice to make.
public enum ThreadSafeMechanism: Sendable {
    /// `OSAllocatedUnfairLock`. Low-contention, short critical sections. Every access — reads
    /// included — is fully exclusive; there's no concurrent-reads case to make here.
    case lock
    /// `DispatchQueue`, concurrent with barrier writes: reads run in parallel, writes are
    /// exclusive. A subscript's in-place modify (`ts[i] += 1`, `ts[i]?.append(x)`, plain
    /// `ts[i] = v`) "parks" the queue for the duration instead of running inside a `sync` call —
    /// roughly 6µs per compound edit (two semaphore round-trips), and it blocks a GCD worker
    /// thread for that whole window, which can stall other low-QoS work queued behind it. Prefer
    /// `.readerWriterLock` or `.lock` for hot-path or main-thread compound subscript edits.
    case dispatchQueue
    /// `pthread_rwlock_t`, locked manually: concurrent reads, exclusive writes, the same
    /// semantics as `.dispatchQueue` but with no backing queue to park — a subscript's in-place
    /// modify holds the write lock directly across its `yield`, so compound edits are cheap.
    case readerWriterLock
}
