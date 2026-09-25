#if canImport(Darwin)
import Darwin
#endif

/// Per-thread record of held instances so `.readerWriterLock` traps on reentry instead of hanging.
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
