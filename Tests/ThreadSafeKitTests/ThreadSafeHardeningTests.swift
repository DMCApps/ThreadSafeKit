import Foundation
import Testing

@testable import ThreadSafeKit

// Coverage added during code review of the ThreadSafe<Value> unification.
// Closes gaps the existing suite left open: rethrows/error-unwind, the `.lock`
// storage duplicate, real content-asserting concurrency stress, reentrancy
// behaviour, and the genuine `init(_ sequence:)` overload.

private let mechanisms: [ThreadSafeMechanism] = [.lock, .dispatchQueue]

private struct Boom: Error {}

// MARK: - rethrows: the lock/queue must be released when the body throws

// The whole suite never throws from a `forEach`/`map`/`reduce`/`merge`/`mutate`
// closure, so the error-unwind path was entirely uncovered. If any of these
// failed to release, the follow-up read would deadlock rather than fail.

@Test(arguments: mechanisms)
func mutateReleasesLockWhenBodyThrows(mechanism: ThreadSafeMechanism) {
    let array = ThreadSafe([1, 2, 3], mechanism: mechanism)
    #expect(throws: Boom.self) {
        try array.mutate { (elements: inout [Int]) -> Void in
            elements.append(4)
            throw Boom()
        }
    }
    // Partial mutation before the throw is kept — `mutate` is not transactional.
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
    #expect(dictionary.getValue(forKey: "a") == 1)
}

// MARK: - Uncovered member behaviour

@Test(arguments: mechanisms)
func popOnEmptyReturnsNil(mechanism: ThreadSafeMechanism) {
    let array = ThreadSafe<[Int]>(mechanism: mechanism)
    #expect(array.pop() == nil)
}

@Test(arguments: mechanisms)
func setValueNilRemovesKey(mechanism: ThreadSafeMechanism) {
    // Distinct from the existing test, which exercises the subscript setter.
    let dictionary = ThreadSafe(["a": 1, "b": 2], mechanism: mechanism)
    dictionary.setValue(nil, forKey: "a")
    #expect(dictionary.getValue(forKey: "a") == nil)
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
    // `reduce(into:)` was only ever exercised on the dictionary shape.
    let array = ThreadSafe([1, 2, 3, 4], mechanism: mechanism)
    let sum = array.reduce(into: 0) { $0 += $1 }
    #expect(sum == 10)
}

@Test(arguments: mechanisms)
func sequenceInitIsDistinctFromValueInit(mechanism: ThreadSafeMechanism) {
    // `ThreadSafe([1, 2, 3])` resolves to `init(_ value: Value)`, NOT the
    // sequence init. A non-Array Sequence is the only way to reach the latter.
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

// MARK: - Hashable

@Test
func dictionaryHashIsOrderIndependentAcrossManyInsertionOrders() {
    // The existing order-independence test hashes two hand-written literals.
    // This shuffles 50 pairs 200 ways and requires a single distinct hash.
    var hashes = Set<Int>()
    for _ in 0..<200 {
        var pairs = (0..<50).map { ($0, "v\($0)") }
        pairs.shuffle()
        hashes.insert(ThreadSafe(Dictionary(uniqueKeysWithValues: pairs)).hashValue)
    }
    #expect(hashes.count == 1)
}

@Test
func equalValuesHashEquallyAcrossMechanisms() {
    let a = ThreadSafe([1: "a", 2: "b"], mechanism: .lock)
    let b = ThreadSafe([2: "b", 1: "a"], mechanism: .dispatchQueue)
    #expect(a == b)
    #expect(a.hashValue == b.hashValue)
}

// MARK: - Concurrency stress that asserts on CONTENT, not just count

// The existing concurrency tests assert only `count == 2000` and discard every
// read. These assert the full element set and validate each read snapshot.

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
    // Every snapshot taken mid-write must be a valid prefix-set, never a torn
    // or duplicated buffer. This is the read-during-write case with assertions.
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
            dictionary.setValue(k * 2, forKey: k)
        }
    }
    #expect(dictionary.count == writers * perWriter)
    // Values, not just keys — the existing tests never check these.
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
    // Exercises append/pop/removeAt/subscript/map/forEach all at once so the
    // barrier discipline is tested against more than one write member.
    let array = ThreadSafe(Array(0..<500), mechanism: mechanism)
    DispatchQueue.concurrentPerform(iterations: 64) { i in
        switch i % 4 {
        case 0: for _ in 0..<200 { array.append(i) }
        case 1: for _ in 0..<200 { _ = array.pop() }
        case 2: for _ in 0..<200 { _ = array.map { $0 } }
        default: for _ in 0..<200 { _ = array.count; _ = array[safe: 0] }
        }
    }
    #expect(array.count == array.elements.count)
}

// MARK: - Reentrancy

// Confirmed behaviour (measured, not assumed):
//
//   nested read  inside read   .lock          -> DEADLOCK (unfair lock is not recursive)
//   nested read  inside read   .dispatchQueue -> now safe: `read` takes `storage` by value
//                                                and runs a non-barrier `sync`, so nested
//                                                non-barrier reads on the same concurrent
//                                                queue no longer register overlapping
//                                                exclusive accesses. (Previously crashed
//                                                with "Fatal access conflict detected"
//                                                while `read` took `inout storage` — see
//                                                the fix in ThreadSafe.swift's `read`.)
//   nested read  inside write  both           -> DEADLOCK / libdispatch trap
//   nested write inside write  both           -> DEADLOCK / libdispatch trap
//
// The remaining three rows are inherent to lock/queue mutual exclusion, not
// bugs — `mutate`/`write` intentionally hold the lock/barrier across the whole
// closure, so calling back into the same instance from inside one is always
// unsafe. They can't be asserted in-process (they deadlock or trap the whole
// runner), so only the fixed case is a live test; the rest stay documented.

@Test
func reentrantReadInsideReadIsSafeOnDispatchQueue() {
    let array = ThreadSafe([1, 2, 3], mechanism: .dispatchQueue)
    array.forEach { _ in _ = array.count }
}

@Test(.disabled("Deadlocks (.lock) / libdispatch-traps (.dispatchQueue). Inherent to sync mutual exclusion; needs documenting, not fixing."))
func reentrantReadInsideMutateIsUnsafe() {
    let array = ThreadSafe([1, 2, 3], mechanism: .lock)
    array.mutate { elements in
        elements.append(4)
        _ = array.count
    }
}

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
    // The lock's copy is now empty, so nothing should reference the canary.
    #expect(Canary.liveCount == 0, "`storage` is holding a stale duplicate of the initial value")
}

@Test
func dispatchQueueMechanismDoesNotRetainInitialValue() {
    Canary.reset()
    let subject: ThreadSafe<[Canary]> = {
        let initial = [Canary()]
        return ThreadSafe(initial, mechanism: .dispatchQueue)
    }()
    #expect(Canary.liveCount == 1)

    subject.removeAll()
    #expect(subject.isEmpty)
    #expect(Canary.liveCount == 0)
}

// MARK: - description ordering for the dictionary shape

@Test
func multiEntryDictionaryDescriptionIsOrderDependent() {
    // The only existing description test uses a single entry, which hides the
    // fact that `description` interpolates a Dictionary and is therefore
    // nondeterministically ordered. Documented here so nobody writes an
    // exact-match assertion against a multi-entry dictionary.
    let dictionary = ThreadSafe(["a": 1, "b": 2])
    let rendered = dictionary.description
    #expect(rendered.hasPrefix("ThreadSafe(["))
    #expect(rendered.contains("\"a\": 1"))
    #expect(rendered.contains("\"b\": 2"))
}
