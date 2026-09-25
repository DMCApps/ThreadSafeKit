import Foundation
import Testing

@testable import ThreadSafeKit

// Error-unwind, retention, content-asserting stress, reentrancy, and sequence-init coverage.

private let mechanisms: [ThreadSafeMechanism] = [.lock, .readerWriterLock]

private struct Boom: Error {}

// MARK: - Equatable

@Test
func equalValuesCompareEqualAcrossMechanisms() {
    let a = ThreadSafe([1: "a", 2: "b"], mechanism: .lock)
    let b = ThreadSafe([2: "b", 1: "a"], mechanism: .readerWriterLock)
    #expect(a == b)
}

// MARK: - rethrows: the lock must be released when the body throws

// If release-on-throw broke, the follow-up read would deadlock.

@Test(arguments: mechanisms)
func mutateReleasesLockWhenBodyThrows(mechanism: ThreadSafeMechanism) {
    let array = ThreadSafe([1, 2, 3], mechanism: mechanism)
    #expect(throws: Boom.self) {
        try array.mutate { (elements: inout [Int]) -> Void in
            elements.append(4)
            throw Boom()
        }
    }
    // Pre-throw mutation is kept; `mutate` isn't transactional.
    #expect(array.elements == [1, 2, 3, 4])
}

@Test(arguments: mechanisms)
func forEachReleasesLockWhenBodyThrows(mechanism: ThreadSafeMechanism) {
    let array = ThreadSafe([1, 2, 3], mechanism: mechanism)
    #expect(throws: Boom.self) { try array.forEach { _ in throw Boom() } }
    #expect(array.count == 3)
}

@Test(arguments: mechanisms)
func mapReleasesLockWhenBodyThrows(mechanism: ThreadSafeMechanism) {
    let array = ThreadSafe([1, 2, 3], mechanism: mechanism)
    #expect(throws: Boom.self) { try array.map { _ -> Int in throw Boom() } }
    #expect(array.count == 3)
}

@Test(arguments: mechanisms)
func reduceReleasesLockWhenBodyThrows(mechanism: ThreadSafeMechanism) {
    let array = ThreadSafe([1, 2, 3], mechanism: mechanism)
    #expect(throws: Boom.self) {
        try array.reduce(into: 0) { _, _ in throw Boom() }
    }
    #expect(array.count == 3)
}

@Test(arguments: mechanisms)
func mergeReleasesLockWhenCombineThrows(mechanism: ThreadSafeMechanism) {
    let dictionary = ThreadSafe(["a": 1], mechanism: mechanism)
    #expect(throws: Boom.self) {
        try dictionary.merge(["a": 2]) { _, _ in throw Boom() }
    }
    #expect(dictionary["a"] == 1)
}

// MARK: - Uncovered member behaviour

@Test(arguments: mechanisms)
func popLastOnEmptyReturnsNil(mechanism: ThreadSafeMechanism) {
    let array = ThreadSafe<[Int]>(mechanism: mechanism)
    #expect(array.popLast() == nil)
}

@Test(arguments: mechanisms)
func subscriptAssignmentToNilRemovesKey(mechanism: ThreadSafeMechanism) {
    let dictionary = ThreadSafe(["a": 1, "b": 2], mechanism: mechanism)
    dictionary["a"] = nil
    #expect(dictionary["a"] == nil)
    #expect(dictionary.count == 1)
}

@Test(arguments: mechanisms)
func removeAllKeepingCapacity(mechanism: ThreadSafeMechanism) {
    let array = ThreadSafe(Array(0..<100), mechanism: mechanism)
    array.removeAll(keepingCapacity: true)
    #expect(array.isEmpty)
    let dictionary = ThreadSafe(Dictionary(uniqueKeysWithValues: (0..<100).map { ($0, $0) }), mechanism: mechanism)
    dictionary.removeAll(keepingCapacity: true)
    #expect(dictionary.isEmpty)
}

@Test(arguments: mechanisms)
func reduceOnArrayShape(mechanism: ThreadSafeMechanism) {
    // Covers `reduce(into:)` on the array shape.
    let array = ThreadSafe([1, 2, 3, 4], mechanism: mechanism)
    let sum = array.reduce(into: 0) { $0 += $1 }
    #expect(sum == 10)
}

@Test(arguments: mechanisms)
func sequenceInitIsDistinctFromValueInit(mechanism: ThreadSafeMechanism) {
    // Array literals pick `init(_ value:)`, so a non-Array sequence is needed to reach the sequence init.
    let fromRange = ThreadSafe<[Int]>(0..<5, mechanism: mechanism)
    #expect(fromRange.elements == [0, 1, 2, 3, 4])

    let fromSet = ThreadSafe<[Int]>(Set([7]), mechanism: mechanism)
    #expect(fromSet.elements == [7])

    let empty = ThreadSafe<[Int]>(mechanism: mechanism)
    #expect(empty.isEmpty)
}

@Test(arguments: mechanisms)
func removeAtReturnsElementAndIsDiscardable(mechanism: ThreadSafeMechanism) {
    let array = ThreadSafe([10, 20, 30], mechanism: mechanism)
    array.remove(at: 0)  // @discardableResult path
    #expect(array.elements == [20, 30])
    #expect(array.remove(at: 1) == 30)
}

// MARK: - mutate signature is a strict superset of the old atomic signature

@Test(arguments: mechanisms)
func mutateAcceptsOldVoidReturningCallShapes(mechanism: ThreadSafeMechanism) {
    let counter = ThreadSafe(0, mechanism: mechanism)

    // Old shape: trailing closure returning Void.
    counter.mutate { $0 += 1 }
    #expect(counter.wrappedValue == 1)

    // Old shape: a stored `(inout Value) -> Void` function value.
    let bump: @Sendable (inout Int) -> Void = { $0 += 10 }
    counter.mutate(bump)
    #expect(counter.wrappedValue == 11)

    // New capability: a value can be carried out of the critical section.
    let doubled: Int = counter.mutate { value in
        value *= 2
        return value
    }
    #expect(doubled == 22)
    #expect(counter.wrappedValue == 22)
}

// MARK: - Concurrency stress that asserts on CONTENT, not just count

// These assert full contents and validate every read snapshot.

@Test(arguments: mechanisms)
func concurrentAppendsPreserveEveryElement(mechanism: ThreadSafeMechanism) {
    let array = ThreadSafe<[Int]>(mechanism: mechanism)
    let writers = 8
    let perWriter = 2_000
    DispatchQueue.concurrentPerform(iterations: writers) { w in
        for j in 0..<perWriter { array.append(w * perWriter + j) }
    }
    #expect(array.count == writers * perWriter)
    #expect(Set(array.elements) == Set(0..<(writers * perWriter)))
}

@Test(arguments: mechanisms)
func concurrentReadSnapshotsAreInternallyConsistent(mechanism: ThreadSafeMechanism) {
    // Mid-write snapshots must be valid, untorn buffers.
    let array = ThreadSafe<[Int]>(mechanism: mechanism)
    DispatchQueue.concurrentPerform(iterations: 16) { i in
        if i % 2 == 0 {
            for j in 0..<1_000 { array.append(i * 1_000 + j) }
        } else {
            for _ in 0..<1_000 {
                let snapshot = array.elements
                #expect(Set(snapshot).count == snapshot.count, "torn/duplicated read snapshot")
            }
        }
    }
    #expect(array.count == 8 * 1_000)
}

@Test(arguments: mechanisms)
func concurrentDictionaryWritesPreserveEveryEntry(mechanism: ThreadSafeMechanism) {
    let dictionary = ThreadSafe<[Int: Int]>(mechanism: mechanism)
    let writers = 8
    let perWriter = 2_000
    DispatchQueue.concurrentPerform(iterations: writers) { w in
        for j in 0..<perWriter {
            let k = w * perWriter + j
            dictionary[k] = k * 2
        }
    }
    #expect(dictionary.count == writers * perWriter)
    // Checks values, not just keys.
    #expect(dictionary.dictionary.allSatisfy { $0.value == $0.key * 2 })
}

@Test(arguments: mechanisms)
func concurrentAtomicReadModifyWriteLosesNothing(mechanism: ThreadSafeMechanism) {
    let counter = ThreadSafe(0, mechanism: mechanism)
    let workers = 8
    let per = 5_000
    DispatchQueue.concurrentPerform(iterations: workers * 2) { i in
        if i < workers {
            for _ in 0..<per { counter.mutate { $0 += 1 } }
        } else {
            for _ in 0..<per { _ = counter.wrappedValue }
        }
    }
    #expect(counter.wrappedValue == workers * per)
}

@Test(arguments: mechanisms)
func concurrentMixedShapeOperationsStayConsistent(mechanism: ThreadSafeMechanism) {
    // Mixed writes must leave only seed or appended values, with the count matching successful pops.
    let initial = Array(0..<500)
    let array = ThreadSafe(initial, mechanism: mechanism)
    let successfulPops = ThreadSafe(0, mechanism: .lock)
    let appendIterations = (0..<64).filter { $0 % 4 == 0 }
    let appends = appendIterations.count * 200

    DispatchQueue.concurrentPerform(iterations: 64) { i in
        switch i % 4 {
        case 0:
            // Offset so appended values differ from the seed range.
            for _ in 0..<200 { array.append(1_000 + i) }
        case 1:
            for _ in 0..<200 {
                if array.popLast() != nil {
                    successfulPops.mutate { $0 += 1 }
                }
            }
        case 2: for _ in 0..<200 { _ = array.map { $0 } }
        default: for _ in 0..<200 { _ = array.count; _ = array[safe: 0] }
        }
    }

    let expectedCount = 500 + appends - successfulPops.wrappedValue
    #expect(array.count == expectedCount)

    let initialValues = Set(initial)
    let appendedValues = Set(appendIterations.map { 1_000 + $0 })
    #expect(array.elements.allSatisfy { initialValues.contains($0) || appendedValues.contains($0) })
}

// MARK: - Reentrancy

// Same-thread reentrancy traps: natively under `.lock`, via `ReentrancyTracker` under `.readerWriterLock`.

#if os(macOS)
// Exit tests can't capture state, so one function per mechanism, kept few to avoid exhausting the runner's threads.

@Test(.timeLimit(.minutes(1)))
func reentrantReadInsideReadAbortsOnLock() async {
    await #expect(processExitsWith: .failure) {
        let array = ThreadSafe([1, 2, 3], mechanism: .lock)
        array.forEach { _ in _ = array.count }
    }
}

@Test(.timeLimit(.minutes(1)))
func reentrantReadInsideReadAbortsOnReaderWriterLock() async {
    await #expect(processExitsWith: .failure) {
        let array = ThreadSafe([1, 2, 3], mechanism: .readerWriterLock)
        array.forEach { _ in _ = array.count }
    }
}

@Test(.timeLimit(.minutes(1)))
func reentrantReadInsideMutateAbortsOnLock() async {
    await #expect(processExitsWith: .failure) {
        let array = ThreadSafe([1, 2, 3], mechanism: .lock)
        array.mutate { elements in
            elements.append(4)
            _ = array.count
        }
    }
}

@Test(.timeLimit(.minutes(1)))
func reentrantReadInsideMutateAbortsOnReaderWriterLock() async {
    await #expect(processExitsWith: .failure) {
        let array = ThreadSafe([1, 2, 3], mechanism: .readerWriterLock)
        array.mutate { elements in
            elements.append(4)
            _ = array.count
        }
    }
}

@Test(.timeLimit(.minutes(1)))
func reentrantWriteInsideWriteAbortsOnLock() async {
    await #expect(processExitsWith: .failure) {
        let array = ThreadSafe([1, 2, 3], mechanism: .lock)
        array.mutate { _ in
            array.mutate { $0.append(5) }
        }
    }
}

@Test(.timeLimit(.minutes(1)))
func reentrantWriteInsideWriteAbortsOnReaderWriterLock() async {
    await #expect(processExitsWith: .failure) {
        let array = ThreadSafe([1, 2, 3], mechanism: .readerWriterLock)
        array.mutate { _ in
            array.mutate { $0.append(5) }
        }
    }
}

@Test(.timeLimit(.minutes(1)))
func reentrantWriteInsideReadAbortsOnLock() async {
    await #expect(processExitsWith: .failure) {
        let array = ThreadSafe([1, 2, 3], mechanism: .lock)
        array.forEach { _ in array.append(4) }
    }
}

@Test(.timeLimit(.minutes(1)))
func reentrantWriteInsideReadAbortsOnReaderWriterLock() async {
    await #expect(processExitsWith: .failure) {
        let array = ThreadSafe([1, 2, 3], mechanism: .readerWriterLock)
        array.forEach { _ in array.append(4) }
    }
}

// A predicate reading the instance mid-`removeAll(where:)` is write-in-write reentry and must trap.
@Test(.timeLimit(.minutes(1)))
func reentrantRemoveAllWhereAbortsOnLock() async {
    await #expect(processExitsWith: .failure) {
        let array = ThreadSafe([1, 2, 3], mechanism: .lock)
        array.removeAll { _ in array.count > 0 }
    }
}

@Test(.timeLimit(.minutes(1)))
func reentrantRemoveAllWhereAbortsOnReaderWriterLock() async {
    await #expect(processExitsWith: .failure) {
        let array = ThreadSafe([1, 2, 3], mechanism: .readerWriterLock)
        array.removeAll { _ in array.count > 0 }
    }
}

// A mutating method on `array[0]` that modifies `array[1]` nests two `_modify` accesses, unlike `array[0] += array.count`.
private struct ReentrancyProbe {
    var value: Int

    mutating func incrementAndModify(at index: Int, in array: ThreadSafe<[ReentrancyProbe]>) {
        value += 1
        array[index].value += 1  // reentrant modify while this element's own `_modify` is still held
    }
}

@Test(.timeLimit(.minutes(1)))
func reentrantModifyInsideModifyAbortsOnLock() async {
    await #expect(processExitsWith: .failure) {
        let array = ThreadSafe([ReentrancyProbe(value: 1), ReentrancyProbe(value: 2)], mechanism: .lock)
        array[0].incrementAndModify(at: 1, in: array)
    }
}

@Test(.timeLimit(.minutes(1)))
func reentrantModifyInsideModifyAbortsOnReaderWriterLock() async {
    await #expect(processExitsWith: .failure) {
        let array = ThreadSafe([ReentrancyProbe(value: 1), ReentrancyProbe(value: 2)], mechanism: .readerWriterLock)
        array[0].incrementAndModify(at: 1, in: array)
    }
}

// Reentry traps for dictionary and set shapes under `.readerWriterLock`.
@Test(.timeLimit(.minutes(1)))
func reentrantWriteInsideWriteAbortsOnReaderWriterLock_Dictionary() async {
    await #expect(processExitsWith: .failure) {
        let dict = ThreadSafe(["a": 1], mechanism: .readerWriterLock)
        dict.mutate { _ in
            dict["b"] = 2
        }
    }
}

@Test(.timeLimit(.minutes(1)))
func reentrantWriteInsideWriteAbortsOnReaderWriterLock_Set() async {
    await #expect(processExitsWith: .failure) {
        let set = ThreadSafe<Set<Int>>([1, 2, 3], mechanism: .readerWriterLock)
        set.mutate { _ in
            _ = set.insert(4)
        }
    }
}
#endif

// MARK: - Reentrancy: nesting distinct instances (must never trap)

// Nesting distinct instances must work at any depth, including past the tracker's inline capacity.
@Test(arguments: mechanisms)
func nestingManyDistinctInstancesOnSameThreadNeverTraps(mechanism: ThreadSafeMechanism) {
    let counters = (0..<6).map { _ in ThreadSafe(0, mechanism: mechanism) }

    @Sendable func nest(_ index: Int) {
        guard index < counters.count else { return }
        counters[index].mutate { value in
            value += 1
            nest(index + 1)
        }
    }
    nest(0)

    for counter in counters {
        #expect(counter.wrappedValue == 1)
    }
}

// A throw inside a nested access must not leave a stale tracker entry.
@Test
func nestedThrowLeavesNoStaleTrackerEntryOnReaderWriterLock() {
    let outer = ThreadSafe(0, mechanism: .readerWriterLock)
    let inner = ThreadSafe(0, mechanism: .readerWriterLock)

    #expect(throws: Boom.self) {
        try outer.mutate { _ in
            try inner.mutate { _ in
                throw Boom()
            }
        }
    }

    outer.mutate { $0 += 1 }
    inner.mutate { $0 += 1 }
    #expect(outer.wrappedValue == 1)
    #expect(inner.wrappedValue == 1)
}

// Concurrent per-thread nesting must never leak or collide tracker state.
@Test(.timeLimit(.minutes(1)))
func concurrentNestingOfDifferentInstancesNeverFalseTrapsOnReaderWriterLock() {
    let a = ThreadSafe(0, mechanism: .readerWriterLock)
    let b = ThreadSafe(0, mechanism: .readerWriterLock)
    let c = ThreadSafe(0, mechanism: .readerWriterLock)
    let perThread = 2000

    DispatchQueue.concurrentPerform(iterations: 8) { _ in
        for _ in 0..<perThread {
            a.mutate { aValue in
                aValue += 1
                b.mutate { bValue in
                    bValue += 1
                    c.mutate { cValue in
                        cValue += 1
                    }
                }
            }
        }
    }

    #expect(a.wrappedValue == 8 * perThread)
    #expect(b.wrappedValue == 8 * perThread)
    #expect(c.wrappedValue == 8 * perThread)
}

#if os(macOS)
// MARK: - Subscript bounds checking

// Out-of-bounds index traps via `Array`'s own bounds check.

@Test(.timeLimit(.minutes(1)))
func subscriptGetOutOfBoundsTraps() async {
    await #expect(processExitsWith: .failure) {
        let array = ThreadSafe([1, 2, 3], mechanism: .lock)
        _ = array[10]
    }
}

@Test(.timeLimit(.minutes(1)))
func subscriptModifyOutOfBoundsTraps() async {
    await #expect(processExitsWith: .failure) {
        let array = ThreadSafe([1, 2, 3], mechanism: .lock)
        array[10] += 1
    }
}

// MARK: - Async inout hazard
// `modifyOwnerThread` traps cross-thread resumption, but it can't be reproduced reliably in a forked child, so there's no exit test.
#endif

// ThreadSafe is intentionally not Hashable; see ThreadSafe+Conformances.swift.

// MARK: - `.lock` mechanism must not retain a duplicate of the initial value

private final class Canary: @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var live = 0

    static var liveCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return live
    }

    static func reset() {
        lock.lock()
        live = 0
        lock.unlock()
    }

    init() {
        Canary.lock.lock()
        Canary.live += 1
        Canary.lock.unlock()
    }

    deinit {
        Canary.lock.lock()
        Canary.live -= 1
        Canary.lock.unlock()
    }
}

@Test
func lockMechanismDoesNotRetainInitialValue() {
    Canary.reset()
    let subject: ThreadSafe<[Canary]> = {
        let initial = [Canary()]
        return ThreadSafe(initial, mechanism: .lock)
    }()
    #expect(Canary.liveCount == 1)

    subject.removeAll()
    #expect(subject.isEmpty)
    // Emptied storage must release the canary.
    #expect(Canary.liveCount == 0, "`storage` is holding a stale duplicate of the initial value")
}

// MARK: - description ordering for the dictionary shape

@Test
func multiEntryDictionaryDescriptionIsOrderDependent() {
    // Multi-entry dictionary descriptions are unordered, so only check contents.
    let dictionary = ThreadSafe(["a": 1, "b": 2])
    let rendered = dictionary.description
    #expect(rendered.hasPrefix("ThreadSafe(["))
    #expect(rendered.contains("\"a\": 1"))
    #expect(rendered.contains("\"b\": 2"))
}
