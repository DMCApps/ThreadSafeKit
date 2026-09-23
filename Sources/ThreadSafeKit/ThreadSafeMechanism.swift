/// Backing mechanism for the lock/queue-based thread-safe types (``ThreadSafeArray``, ``ThreadSafeDictionary``,
/// ``ThreadSafeAtomic``). The actor-backed alternatives (``ArrayActor``, ``DictionaryActor``, ``AtomicActor``)
/// don't take this — actor isolation always requires `await`, so there's no sync/mechanism choice to make.
public enum ThreadSafeMechanism: Sendable {
    /// `OSAllocatedUnfairLock`. Real (checked) `Sendable`. Low-contention, short critical sections.
    case lock
    /// `DispatchQueue`. `@unchecked Sendable` — safety enforced internally, not by the compiler.
    case dispatchQueue
}
