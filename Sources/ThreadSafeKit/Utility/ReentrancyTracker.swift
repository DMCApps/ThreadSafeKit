#if canImport(Darwin)
import Darwin
#endif

/// Same-thread reentrancy detection for `ThreadSafe`'s `.readerWriterLock` mechanism
/// (`ThreadSafe.swift`). `.lock` doesn't use this at all — `os_unfair_lock` already traps on a
/// same-thread relock, so tracking would be pure overhead there. `pthread_rwlock` doesn't
/// self-detect reliably: Darwin returns `EDEADLK` for some combinations, but read-in-read
/// succeeds and then deadlocks the moment a writer queues between the two reads. Detecting
/// reentrancy explicitly, ahead of the acquire, gives a deterministic trap instead of that hang.
///
/// Tracks, per OS thread, which instances that thread currently holds a read/write/modify access
/// to, and traps *before* attempting to acquire the rwlock a thread already holds — the whole
/// point is avoiding a hang, so the check has to happen ahead of the acquire, not after.
///
/// Storage is an inline fixed-capacity buffer scanned linearly, not a `Set`: nesting depth (how
/// many *distinct* instances a thread has active at once, e.g. `a.mutate { b.mutate { ... } }`)
/// is almost always 0 or 1, occasionally a handful — small enough that a linear scan beats
/// hashing, and small enough to size inline with zero heap allocation in the common case. A
/// thread that nests deeper than the inline capacity falls back to a heap array; that thread's
/// `Box` (allocated once, lazily, and reused for the rest of the thread's life) is the only
/// per-thread state, so this fallback allocates at most once per thread, not once per access.
@usableFromInline
enum ReentrancyTracker {
    private final class Box {
        static let inlineCapacity = 4

        private let slots: UnsafeMutablePointer<ObjectIdentifier?>
        private var slotCount = 0
        private var overflow: [ObjectIdentifier] = []

        init() {
            slots = .allocate(capacity: Self.inlineCapacity)
            slots.initialize(repeating: nil, count: Self.inlineCapacity)
        }

        deinit {
            slots.deinitialize(count: Self.inlineCapacity)
            slots.deallocate()
        }

        func contains(_ id: ObjectIdentifier) -> Bool {
            for i in 0..<slotCount where slots[i] == id { return true }
            return !overflow.isEmpty && overflow.contains(id)
        }

        func insert(_ id: ObjectIdentifier) {
            if slotCount < Self.inlineCapacity {
                slots[slotCount] = id
                slotCount += 1
            } else {
                overflow.append(id)
            }
        }

        func remove(_ id: ObjectIdentifier) {
            for i in 0..<slotCount where slots[i] == id {
                slotCount -= 1
                slots[i] = slots[slotCount]
                slots[slotCount] = nil
                return
            }
            if let index = overflow.firstIndex(of: id) {
                overflow.remove(at: index)
            }
        }
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
    @usableFromInline
    static func beginAccess(_ instance: AnyObject) -> Bool {
        let box = currentBox()
        let id = ObjectIdentifier(instance)
        guard !box.contains(id) else { return false }
        box.insert(id)
        return true
    }

    @usableFromInline
    static func endAccess(_ instance: AnyObject) {
        currentBox().remove(ObjectIdentifier(instance))
    }
}
