#if canImport(Darwin)
import Darwin
#endif

/// Thin wrapper around `pthread_rwlock_t`: concurrent reads, exclusive writes, but — unlike
/// `OSAllocatedUnfairLock`'s closure-based `withLock`/`DispatchQueue.sync` — locked/unlocked
/// manually, so a write lock can be held across a subscript `_modify`'s `yield` (you can't
/// `yield` from inside a closure passed to either of those).
@usableFromInline
final class ReaderWriterLock: @unchecked Sendable {
    private let lock: UnsafeMutablePointer<pthread_rwlock_t>

    @usableFromInline
    init() {
        lock = .allocate(capacity: 1)
        let status = pthread_rwlock_init(lock, nil)
        precondition(status == 0, "pthread_rwlock_init failed with status \(status)")
    }

    deinit {
        let status = pthread_rwlock_destroy(lock)
        precondition(status == 0, "pthread_rwlock_destroy failed with status \(status)")
        lock.deallocate()
    }

    @usableFromInline
    func readLock() {
        let status = pthread_rwlock_rdlock(lock)
        precondition(status == 0, "pthread_rwlock_rdlock failed with status \(status)")
    }

    @usableFromInline
    func writeLock() {
        let status = pthread_rwlock_wrlock(lock)
        precondition(status == 0, "pthread_rwlock_wrlock failed with status \(status)")
    }

    @usableFromInline
    func unlock() {
        let status = pthread_rwlock_unlock(lock)
        precondition(status == 0, "pthread_rwlock_unlock failed with status \(status)")
    }
}
