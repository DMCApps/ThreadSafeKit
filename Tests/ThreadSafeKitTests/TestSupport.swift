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

/// Asserts `body`, called `sampleSize` times, averages under `maxMicroseconds` per call.
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
/// Actor calls carry real hop/scheduling overhead, so the default ceiling is looser than
/// the synchronous one.
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

/// Asserts `wrapped` doesn't average more than `maxOverhead`x the per-call cost of `raw`,
/// each sampled `sampleSize` times back-to-back (so both see comparable CPU/scheduler
/// conditions). Bounded by ratio, not absolute time, so it stays meaningful across
/// machines/CI load — same rationale as the collection-size regression tests in
/// ThreadSafePerformanceTests.swift. `minFloorNanoseconds` guards against flakiness when
/// `raw` itself is near-zero: without it, tiny measurement noise in `raw` could make the
/// ratio swing wildly even though the absolute cost of `wrapped` is trivial.
func assertOverheadBounded(
    _ label: String,
    sampleSize: Int = 5_000,
    maxOverhead: Double = 40.0,
    minFloorNanoseconds: Double = 40_000,
    sourceLocation: SourceLocation = #_sourceLocation,
    raw: () -> Void,
    wrapped: () -> Void
) {
    let rawNs = averageNanoseconds(over: sampleSize, raw)
    let wrappedNs = averageNanoseconds(over: sampleSize, wrapped)
    let ceiling = max(rawNs * maxOverhead, minFloorNanoseconds)
    #expect(
        wrappedNs < ceiling,
        "\(label): wrapped (\(wrappedNs) ns/op) exceeded \(maxOverhead)x raw (\(rawNs) ns/op) — ceiling was \(ceiling) ns/op",
        sourceLocation: sourceLocation
    )
}

/// Actor-hop cost via `await` dwarfs raw synchronous access regardless of what the actor's
/// body does — this bounds the wrapper against a *real* regression (e.g. an accidental O(n)
/// copy inside the actor method) without tripping on that inherent, unavoidable hop cost.
func assertOverheadBounded(
    _ label: String,
    sampleSize: Int = 1_000,
    maxOverhead: Double = 300.0,
    minFloorNanoseconds: Double = 20_000,
    sourceLocation: SourceLocation = #_sourceLocation,
    raw: () -> Void,
    wrapped: () async -> Void
) async {
    let rawNs = averageNanoseconds(over: sampleSize, raw)
    let wrappedNs = await averageNanoseconds(over: sampleSize, wrapped)
    let ceiling = max(rawNs * maxOverhead, minFloorNanoseconds)
    #expect(
        wrappedNs < ceiling,
        "\(label): wrapped (\(wrappedNs) ns/op) exceeded \(maxOverhead)x raw (\(rawNs) ns/op) — ceiling was \(ceiling) ns/op",
        sourceLocation: sourceLocation
    )
}
