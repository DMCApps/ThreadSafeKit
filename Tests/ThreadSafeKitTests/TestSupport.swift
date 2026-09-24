import Foundation
import Testing

let concurrencyIterations = 2000

extension Tag {
    /// Applied to every timing-based test (fixed absolute-time or relative-overhead ceilings) —
    /// see ThreadSafePerformanceTests.swift, ThreadSafeOverheadTests.swift, and the four
    /// `*ActorPerformanceTests.swift` files. Lets those be run/excluded as a group.
    ///
    /// This toolchain's `swift test --filter`/`--skip` only support regular expressions over test
    /// names (confirmed against `swift test --help`, which documents no `tag:` syntax, and
    /// empirically), not Swift Testing tags — so the tag alone doesn't give a CLI selector. It's
    /// kept anyway as the source of truth for "is this a performance test" (an IDE/Xcode test
    /// plan, or a future SwiftPM version, could filter by it directly); the README's `## Testing`
    /// commands instead rely on the fact that every performance/overhead test name ends in `Fast`,
    /// `Bounded`, or `CostDoesNotScaleWithCollectionSize`, none of which appear in any correctness
    /// test name (verified with `grep -rn "@Test" Tests/ | grep -E "Fast|Bounded"`).
    ///
    /// RULE: every `.performance` test's name MUST end in `Fast`, `Bounded`, or
    /// `CostDoesNotScaleWithCollectionSize`, and no correctness test's name may contain those —
    /// otherwise the README's `--skip`/`--filter` commands silently misclassify it.
    @Tag static var performance: Self
}

/// Average wall-clock nanoseconds per call, over `count` synchronous calls to `body`.
func averageNanoseconds(over count: Int, _ body: () -> Void) -> Double {
    let start = DispatchTime.now()
    for _ in 0..<count { body() }
    return Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / Double(count)
}

/// Average wall-clock nanoseconds per call, over `count` awaited calls to `body`.
func averageNanoseconds(over count: Int, _ body: () async -> Void) async -> Double {
    let start = DispatchTime.now()
    for _ in 0..<count { await body() }
    return Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / Double(count)
}

/// Minimum average nanoseconds per call across `batches` batches of `count` calls. The minimum
/// filters out batches inflated by preemption or parallel-test load, so it's far more stable
/// than a single average.
func minBatchNanoseconds(batches: Int = 7, over count: Int, _ body: () -> Void) -> Double {
    (0..<batches).map { _ in averageNanoseconds(over: count, body) }.min()!
}

/// Async counterpart of `minBatchNanoseconds(batches:over:_:)`.
func minBatchNanoseconds(batches: Int = 7, over count: Int, _ body: () async -> Void) async -> Double {
    var best = Double.infinity
    for _ in 0..<batches { best = min(best, await averageNanoseconds(over: count, body)) }
    return best
}

/// Asserts `body`, called `sampleSize` times, averages under `maxMicroseconds` per call.
///
/// Deliberately loose: a catastrophic-regression guard (hang, lock convoy, accidental O(n) work
/// per call), not a speed measurement. Real calls cost tens of nanoseconds, but `swift test`
/// builds debug, runs tests in parallel, and may run under TSan, so a tight absolute ceiling here
/// would be flaky. `assertOverheadBounded` is the tighter, machine-independent check; the
/// `ThreadSafeKitBenchmarks` executable (`swift run -c release ThreadSafeKitBenchmarks`) is where
/// real per-operation numbers come from.
func assertFast(
    _ label: String,
    sampleSize: Int = 2_000,
    maxMicroseconds: Double = 50,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ body: () -> Void
) {
    let us = averageNanoseconds(over: sampleSize, body) / 1_000
    #expect(
        us < maxMicroseconds,
        "\(label) took \(us) us/op, expected under \(maxMicroseconds) us/op",
        sourceLocation: sourceLocation
    )
}

/// Asserts `body`, awaited `sampleSize` times, averages under `maxMicroseconds` per call.
/// Same catastrophic-regression-only intent as the synchronous overload above.
func assertFast(
    _ label: String,
    sampleSize: Int = 500,
    maxMicroseconds: Double = 300,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ body: () async -> Void
) async {
    let us = await averageNanoseconds(over: sampleSize, body) / 1_000
    #expect(
        us < maxMicroseconds,
        "\(label) took \(us) us/op, expected under \(maxMicroseconds) us/op",
        sourceLocation: sourceLocation
    )
}

/// Asserts `wrapped` costs no more than `maxOverhead`x the per-call cost of `raw`. Bounded by
/// ratio, not absolute time, so it stays meaningful across machines/CI load — same rationale as
/// the collection-size regression tests in ThreadSafePerformanceTests.swift.
///
/// Each side is the *minimum* per-call average over several batches (`minBatchNanoseconds`),
/// not a single average: single averages swung ~30x run-to-run under parallel test load, while
/// batch minimums stay within a few x. Measured wrapped/raw ratios (debug and TSan) peaked around
/// 10-11x, so `maxOverhead` = 25 leaves >2x headroom. `minFloorNanoseconds` only matters when
/// `raw` is so cheap that `raw * maxOverhead` would sit inside measurement noise.
func assertOverheadBounded(
    _ label: String,
    sampleSize: Int = 5_000,
    maxOverhead: Double = 25.0,
    minFloorNanoseconds: Double = 2_000,
    sourceLocation: SourceLocation = #_sourceLocation,
    raw: () -> Void,
    wrapped: () -> Void
) {
    let rawNs = minBatchNanoseconds(over: sampleSize, raw)
    let wrappedNs = minBatchNanoseconds(over: sampleSize, wrapped)
    let ceiling = max(rawNs * maxOverhead, minFloorNanoseconds)
    #expect(
        wrappedNs < ceiling,
        "\(label): wrapped (\(wrappedNs) ns/op) exceeded \(maxOverhead)x raw (\(rawNs) ns/op) — ceiling was \(ceiling) ns/op",
        sourceLocation: sourceLocation
    )
}

/// Async counterpart for the actor types. Uncontended actor calls measured only ~1-2x raw, but
/// actor scheduling is more sensitive to parallel-test contention than a lock, so the defaults
/// are looser than the synchronous overload's.
func assertOverheadBounded(
    _ label: String,
    sampleSize: Int = 1_000,
    maxOverhead: Double = 50.0,
    minFloorNanoseconds: Double = 5_000,
    sourceLocation: SourceLocation = #_sourceLocation,
    raw: () -> Void,
    wrapped: () async -> Void
) async {
    let rawNs = minBatchNanoseconds(over: sampleSize, raw)
    let wrappedNs = await minBatchNanoseconds(over: sampleSize, wrapped)
    let ceiling = max(rawNs * maxOverhead, minFloorNanoseconds)
    #expect(
        wrappedNs < ceiling,
        "\(label): wrapped (\(wrappedNs) ns/op) exceeded \(maxOverhead)x raw (\(rawNs) ns/op) — ceiling was \(ceiling) ns/op",
        sourceLocation: sourceLocation
    )
}
