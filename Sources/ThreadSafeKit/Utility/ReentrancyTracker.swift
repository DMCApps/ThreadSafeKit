#if canImport(Darwin)
import Darwin
#endif

/// Same-thread reentrancy detection shared by all three `ThreadSafe` mechanisms. Replaces the old
/// `.dispatchQueue`-only `DispatchSpecificKey` check, which only caught nesting that ran
/// *synchronously inside* a `queue.sync` call: `pthread_rwlock` doesn't self-detect recursion
/// reliably (Darwin returns `EDEADLK` for some combinations, but read-in-read succeeds and then
/// deadlocks the moment a writer queues between the two reads), and `.dispatchQueue`'s subscript
/// `_modify` "parks" the queue rather than running inside a `sync` call, so nothing GCD-native
/// would catch reentrancy during its `yield` either.
///
/// Tracks, per OS thread, which instances that thread currently holds a read/write/modify access
/// to, and traps *before* attempting to acquire a lock the thread already holds — the whole
/// point is avoiding a hang, so the check has to happen ahead of the acquire, not after.
enum ReentrancyTracker {
    private final class Box {
        var active: Set<ObjectIdentifier> = []
    }

    private static let key: pthread_key_t = {
        var key = pthread_key_t()
        let status = pthread_key_create(&key) { rawBox in
            Unmanaged<Box>.fromOpaque(rawBox).release()
        }
        precondition(status == 0, "pthread_key_create failed with status \(status)")
        return key
    }()

    private static func currentBox() -> Box {
        if let raw = pthread_getspecific(key) {
            return Unmanaged<Box>.fromOpaque(raw).takeUnretainedValue()
        }
        let box = Box()
        pthread_setspecific(key, Unmanaged.passRetained(box).toOpaque())
        return box
    }

    /// Returns `false`, with no side effects, if `instance` is already active on this thread.
    static func beginAccess(_ instance: AnyObject) -> Bool {
        let box = currentBox()
        let id = ObjectIdentifier(instance)
        guard !box.active.contains(id) else { return false }
        box.active.insert(id)
        return true
    }

    static func endAccess(_ instance: AnyObject) {
        currentBox().active.remove(ObjectIdentifier(instance))
    }
}
