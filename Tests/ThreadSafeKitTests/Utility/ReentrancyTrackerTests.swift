import Dispatch
import Foundation
import Testing

@testable import ThreadSafeKit

// Direct coverage for `ReentrancyTracker` itself (Sources/ThreadSafeKit/Utility/ReentrancyTracker.swift),
// isolated from `ThreadSafe`'s own read/write/modify plumbing. Every test that gets a successful
// `beginAccess` pairs it with an `endAccess` before returning, so it doesn't leave a stale entry in
// this thread's tracker state for whichever other test next reuses the same thread.

// `@unchecked`: stateless, only ever used for its identity (`ObjectIdentifier`).
private final class Probe: @unchecked Sendable {}

// `@unchecked`: `value` is written on the spawned thread, then read on the caller's thread only
// after `done.wait()` returns — the semaphore signal/wait pair is what actually establishes the
// happens-before edge the compiler can't see here.
private final class Box<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}

@Test
func beginAccessSucceedsOnFirstCall() {
    let probe = Probe()
    #expect(ReentrancyTracker.beginAccess(probe))
    ReentrancyTracker.endAccess(probe)
}

@Test
func beginAccessFailsWhileAlreadyActiveOnSameThread() {
    let probe = Probe()
    #expect(ReentrancyTracker.beginAccess(probe))
    #expect(!ReentrancyTracker.beginAccess(probe), "reentrant beginAccess on the same thread must fail")
    ReentrancyTracker.endAccess(probe)
}

@Test
func beginAccessSucceedsAgainAfterMatchingEndAccess() {
    let probe = Probe()
    #expect(ReentrancyTracker.beginAccess(probe))
    ReentrancyTracker.endAccess(probe)
    #expect(ReentrancyTracker.beginAccess(probe), "beginAccess must succeed again once the matching endAccess has run")
    ReentrancyTracker.endAccess(probe)
}

@Test
func endAccessOnlyClearsTheGivenInstance() {
    let probeA = Probe()
    let probeB = Probe()
    #expect(ReentrancyTracker.beginAccess(probeA))
    #expect(ReentrancyTracker.beginAccess(probeB))

    ReentrancyTracker.endAccess(probeA)

    #expect(ReentrancyTracker.beginAccess(probeA))
    #expect(!ReentrancyTracker.beginAccess(probeB), "probeB is still active — endAccess(probeA) must not have cleared it")

    ReentrancyTracker.endAccess(probeA)
    ReentrancyTracker.endAccess(probeB)
}

// Tracking is per-OS-thread, not global/per-instance-only: a different thread must be free to
// begin its own access to an instance that's active on this thread. (This is exactly the property
// that makes concurrent, non-reentrant callers on different threads unaffected by the tracker.)
//
// Uses `Thread.detachNewThread`, not `DispatchQueue.global().sync` — GCD's `sync` can (and,
// measurably, sometimes does) run the block inline on the calling thread rather than handing off
// to a different one, which would make this test meaningless. A freshly-spawned `Thread` is
// guaranteed to be a different OS thread from the one that spawned it.
@Test(.timeLimit(.minutes(1)))
func trackingIsPerThreadNotGlobal() {
    let probe = Probe()
    #expect(ReentrancyTracker.beginAccess(probe))

    let otherThreadResult = Box<Bool?>(nil)
    let done = DispatchSemaphore(value: 0)
    Thread.detachNewThread {
        otherThreadResult.value = ReentrancyTracker.beginAccess(probe)
        if otherThreadResult.value == true {
            ReentrancyTracker.endAccess(probe)
        }
        done.signal()
    }
    done.wait()

    #expect(otherThreadResult.value == true, "a different thread must be able to begin access to an instance already active on this thread")
    ReentrancyTracker.endAccess(probe)
}

// `Box`'s inline capacity is 4 — nest more than that on one thread to force the heap-array
// overflow path, and confirm it behaves identically to the inline path: every `beginAccess`
// succeeds while nested, and unwinding in the same order frees each one for reuse.
@Test
func nestingBeyondInlineCapacitySucceedsAndUnwindsCleanly() {
    let probes = (0..<9).map { _ in Probe() }

    for probe in probes {
        #expect(ReentrancyTracker.beginAccess(probe), "distinct instances nesting on the same thread must never trap")
    }
    for probe in probes {
        #expect(!ReentrancyTracker.beginAccess(probe), "each nested probe is still active until its own endAccess runs")
    }
    for probe in probes.reversed() {
        ReentrancyTracker.endAccess(probe)
    }
    for probe in probes {
        #expect(ReentrancyTracker.beginAccess(probe), "beginAccess must succeed again once every nested instance has been unwound")
        ReentrancyTracker.endAccess(probe)
    }
}

// Removing an instance that overflowed into the heap array, while other overflowed instances
// are still active, must only clear that one instance — exercises `Box.remove`'s overflow branch
// specifically (as opposed to the inline-slot branch already covered by
// `endAccessOnlyClearsTheGivenInstance`).
@Test
func removingOneOverflowedInstanceLeavesOthersActive() {
    let probes = (0..<6).map { _ in Probe() } // capacity is 4, so probes[4...] overflow
    for probe in probes {
        #expect(ReentrancyTracker.beginAccess(probe))
    }

    ReentrancyTracker.endAccess(probes[4])

    #expect(ReentrancyTracker.beginAccess(probes[4]), "removing one overflowed instance must free it")
    #expect(!ReentrancyTracker.beginAccess(probes[5]), "removing probes[4] must not affect probes[5], the other overflowed instance")

    for probe in probes {
        ReentrancyTracker.endAccess(probe)
    }
}

// Many distinct instances, all concurrently active on many distinct threads, must never
// false-positive against each other — only true same-thread/same-instance reentry should fail.
@Test(.timeLimit(.minutes(1)))
func manyConcurrentNonReentrantInstancesNeverFalsePositive() {
    let workers = 16
    let perWorker = 500
    DispatchQueue.concurrentPerform(iterations: workers) { _ in
        for _ in 0..<perWorker {
            let probe = Probe()
            let began = ReentrancyTracker.beginAccess(probe)
            #expect(began, "a fresh instance on an otherwise-uninvolved thread must always begin access successfully")
            if began {
                ReentrancyTracker.endAccess(probe)
            }
        }
    }
}
