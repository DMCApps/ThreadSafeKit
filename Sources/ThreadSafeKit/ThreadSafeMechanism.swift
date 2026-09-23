/// Backing mechanism for ``ThreadSafe``, the lock/queue-based thread-safe wrapper. The actor-backed
/// alternatives (``ThreadSafeArray``, ``ThreadSafeDictionary``, ``ThreadSafeAtomic``) don't take this —
/// actor isolation always requires `await`, so there's no sync/mechanism choice to make.
public enum ThreadSafeMechanism: Sendable {
    /// `OSAllocatedUnfairLock`. Real (checked) `Sendable`. Low-contention, short critical sections.
    case lock
    /// `DispatchQueue`. `@unchecked Sendable` — safety enforced internally, not by the compiler.
    case dispatchQueue
}
