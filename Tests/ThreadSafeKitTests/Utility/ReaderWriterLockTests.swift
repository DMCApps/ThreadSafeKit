import Dispatch
import Testing

@testable import ThreadSafeKit

// Direct `ReaderWriterLock` coverage, using unguarded state so only the lock under test synchronizes.

// `@unchecked`: mutated only while holding the lock under test.
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
    // Reader A still holds its lock; a second read lock must not block.
    lock.readLock()
    lock.unlock()
    releaseReaderA.signal()
}

// Concurrent increments under the write lock must not lose updates.
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

// Mismatched halves would mean the write lock failed to exclude readers.
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
