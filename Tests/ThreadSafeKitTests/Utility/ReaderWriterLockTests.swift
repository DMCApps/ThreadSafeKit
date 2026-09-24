import Dispatch
import Testing

@testable import ThreadSafeKit

// Direct coverage for `ReaderWriterLock` itself (Sources/ThreadSafeKit/Utility/ReaderWriterLock.swift),
// isolated from `ThreadSafe`'s own locking/parking/reentrancy logic. Shared mutable state below is a
// bare, *unguarded* box mutated only under the lock under test — never a second `ThreadSafe`/other
// lock around it, which would silently provide the real exclusion and mask a broken `ReaderWriterLock`.

// `@unchecked`: every mutation below happens only while holding the `ReaderWriterLock` under
// test, which is the actual thing providing the synchronization the compiler can't see.
private final class Box<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}

@Test(.timeLimit(.minutes(1)))
func readLockAllowsConcurrentReaders() {
    let lock = ReaderWriterLock()
    let readerAHoldsLock = DispatchSemaphore(value: 0)
    let releaseReaderA = DispatchSemaphore(value: 0)

    DispatchQueue.global().async {
        lock.readLock()
        readerAHoldsLock.signal()
        releaseReaderA.wait()
        lock.unlock()
    }

    readerAHoldsLock.wait()
    // Reader A still holds its read lock; a second, independent read lock must not block.
    lock.readLock()
    lock.unlock()
    releaseReaderA.signal()
}

// Deterministic exclusivity check (no timing/sleep): if `writeLock`/`unlock` didn't properly
// exclude other writers, concurrent increments under the lock would lose updates.
@Test(.timeLimit(.minutes(1)))
func writeLockIsMutuallyExclusive() {
    let lock = ReaderWriterLock()
    let counter = Box(0)
    let workers = 8
    let perWorker = 2_000
    DispatchQueue.concurrentPerform(iterations: workers) { _ in
        for _ in 0..<perWorker {
            lock.writeLock()
            counter.value += 1
            lock.unlock()
        }
    }
    #expect(counter.value == workers * perWorker)
}

// A reader must never observe a torn write: `pair`'s two halves are always written together
// under the write lock, so a reader that ever sees them mismatched proves the write lock failed
// to exclude readers (or readers raced each other in a way that corrupted the read).
@Test(.timeLimit(.minutes(1)))
func writeLockExcludesReadersFromTornState() {
    let lock = ReaderWriterLock()
    let pair = Box((0, 0))
    let iterations = 2_000

    DispatchQueue.concurrentPerform(iterations: 9) { i in
        if i == 0 {
            for n in 0..<iterations {
                lock.writeLock()
                pair.value = (n, n)
                lock.unlock()
            }
        } else {
            for _ in 0..<iterations {
                lock.readLock()
                let snapshot = pair.value
                lock.unlock()
                #expect(snapshot.0 == snapshot.1, "reader observed a torn write: \(snapshot)")
            }
        }
    }
}

@Test
func lockUnlockRoundTripsRepeatedly() {
    let lock = ReaderWriterLock()
    for _ in 0..<1_000 {
        lock.readLock()
        lock.unlock()
        lock.writeLock()
        lock.unlock()
    }
}
