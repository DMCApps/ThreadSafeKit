import Dispatch
import Foundation
import Testing

@testable import ThreadSafeKit

// Direct `ReentrancyTracker` coverage; every successful `beginAccess` is paired with `endAccess`.

// `@unchecked`: stateless, only ever used for its identity (`ObjectIdentifier`).
private final class Probe: @unchecked Sendable {}

// `@unchecked`: the semaphore orders the cross-thread write before the read.
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

// Tracking is per thread, so another thread may access an instance active here (real thread, since GCD `sync` can run inline).
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

// Nest past the inline capacity of 4 to hit the heap overflow path.
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

// Removing an overflowed instance must clear only that instance.
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

// Distinct instances on distinct threads must never false-positive.
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
