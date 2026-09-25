#if canImport(Darwin)
import Darwin
#endif

/// Manually locked `pthread_rwlock_t`, so a write lock can be held across a `_modify` `yield`.
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
