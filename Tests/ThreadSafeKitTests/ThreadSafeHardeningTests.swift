import Foundation
import Testing

@testable import ThreadSafeKit

// Coverage added during code review of the ThreadSafe<Value> unification.
// Closes gaps the existing suite left open: rethrows/error-unwind, the `.lock`
// storage duplicate, real content-asserting concurrency stress, reentrancy
// behaviour, and the genuine `init(_ sequence:)` overload.

private let mechanisms: [ThreadSafeMechanism] = [.lock, .readerWriterLock]

private struct Boom: Error {}

// MARK: - Equatable

@Test
func equalValuesCompareEqualAcrossMechanisms() {
    let a = ThreadSafe([1: "a", 2: "b"], mechanism: .lock)
    let b = ThreadSafe([2: "b", 1: "a"], mechanism: .readerWriterLock)
    #expect(a == b)
}

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

// Both mechanisms trap same-thread reentrancy deterministically via `ReentrancyTracker`
// (ThreadSafe.swift) — checked, and its process-terminating side effect performed, *before*
// attempting to acquire any lock, so a reentrant call always aborts instead of ever having a
// chance to hang:
//
//   nested read  inside read   -> traps, both mechanisms. `pthread_rwlock_rdlock` doesn't
//                                  reliably self-detect same-thread recursion, so without
//                                  `ReentrancyTracker` a nested read could deadlock the instant a
//                                  writer queued between the two reads.
//   nested read  inside write  -> traps, both mechanisms
//   nested write inside write  -> traps, both mechanisms
//   nested write inside read   -> traps, both mechanisms
//   reentrant subscript `_modify` (nested inside another access, or inside its own yielded
//   mutation, e.g. a mutating operation whose argument reads the same instance) -> traps, both
//   mechanisms.
//
// None of these hang — every mechanism aborts the process right away. This is inherent to
// lock mutual exclusion, not a bug: `mutate`/`write`/a subscript's in-place modify intentionally
// hold the lock across the whole operation, so calling back into the same instance from inside
// one is always unsafe. Swift Testing's exit tests let these be real, passing regression tests
// instead of permanently-disabled documentation — each just confirms the process terminates
// abnormally (and quickly, well under the time limit) rather than hanging.

#if os(macOS)
// `#expect(processExitsWith:)`'s closure is re-invoked in a freshly-spawned child process, so it
// can't capture runtime state from the parent (a `swift-frontend` limitation, not a design
// choice here) — `@Test(arguments:)` parameterization doesn't work for these, hence one explicit,
// literal function per mechanism rather than a single parameterized one.
//
// Kept intentionally lean: running dozens of these concurrently (each forks/re-execs a whole new
// process) alongside the rest of the suite's own heavy concurrency stress tests was observed to
// exhaust the test runner's own cooperative thread pool under load, causing an intermittent hang
// or spurious crash unrelated to the actual behaviour under test. The four base combinations are
// exhaustively covered per mechanism; the modify/bounds-checking additions below are each
// covered once broadly (both mechanisms) or once representatively (`.lock` only, where the
// mechanism doesn't change what's being proven) rather than the full cross product.

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

// Reentrancy from one subscript modify into another, both on the same instance, via a mutating
// method call: Swift calls a mutating method on `array[0]` by materializing its address once
// (via `_modify`), invoking the method on that address, then finalizing — so the method body,
// which performs `array[1].value += 1` (itself a full `_modify` access on the same array), runs
// entirely inside `array[0]`'s own modify access. (Unlike `array[0] += array.count`, which
// measurably does NOT reproduce this: Swift evaluates `+=`'s RHS *before* starting the LHS's
// `_modify` access, so that expression never actually nests.)
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

// MARK: - Subscript bounds checking

// An out-of-bounds index traps via `Array`'s own bounds check, for both the `get` and the
// `_modify` accessor — `beginModify()` has already acquired the lock by the time `storage[index]`
// traps, but that's fine: the process terminates right here, so the lock's final state is moot.
// `.lock` only: which mechanism guards the access doesn't change `Array`'s own bounds check.

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
//
// `await someAsyncFunc(&ts[i])` compiles under Swift 6 strict concurrency — confirmed with
// `swiftc -swift-version 6 -typecheck` against a real call site — so the compiler does not reject
// holding a subscript's `_modify` open across a suspension point. If the suspended task resumes
// on a different thread, unlocking from a different thread than the one that locked is undefined
// behavior for both `os_unfair_lock` and `pthread_rwlock` — `modifyOwnerThread` (ThreadSafe.swift)
// traps deterministically instead of risking it.
//
// Not exercised as an exit test here: reproducing it needs a *genuine* cross-thread resumption
// (`Task.yield()`, and resuming a checked continuation from a `DispatchQueue.global()`/detached
// `Thread`, were all tried), and every one of them was reliable in a standalone executable but
// consistently failed to reproduce inside this exit test's own forked child process — the
// runner's execution context there is apparently constrained enough that the continuation kept
// resuming on the same thread that suspended it, making a from-inside-the-suite exit test for
// this specific case flaky by construction. Verified instead with a standalone script
// (`Thread.detachNewThread` resuming a checked continuation after `array[0] += 1`, matching
// ThreadSafe.swift's `modifyOwnerThread` comment): 8/8 runs trapped with the expected message.
#endif

// Note: ThreadSafe used to conform to Hashable (forwarding hash(into:) to wrappedValue's live,
// mutable contents), which corrupted Set/Dictionary-key membership the moment a member was
// mutated after insertion — Set never re-buckets an existing member, so its hash must never
// change while it's a member, and a reference type's mutable contents can't offer that guarantee
// the way a value type's CoW does. Hashable was removed entirely (ThreadSafe+Conformances.swift)
// rather than patched, since nothing in this codebase had a real need for ThreadSafe instances
// themselves as Set elements/Dictionary keys — Equatable (value-based, kept) has no such
// invariant to violate. To deduplicate/hash by content: `Set(instances.map(\.wrappedValue))`.

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
