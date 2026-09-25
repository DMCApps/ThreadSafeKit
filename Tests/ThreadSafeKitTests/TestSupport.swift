import Foundation
import Testing

let concurrencyIterations = 2000

extension Tag {
    /// Tag for timing tests, whose names must end in `Fast`, `Bounded`, or `CostDoesNotScaleWithCollectionSize` for the README's `--skip`/`--filter` regexes.
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

/// Minimum average ns per call across batches, filtering out preemption-inflated batches.
func minBatchNanoseconds(batches: Int = 7, over count: Int, _ body: () -> Void) -> Double {
    (0..<batches).map { _ in averageNanoseconds(over: count, body) }.min()!
}

/// Async counterpart of `minBatchNanoseconds(batches:over:_:)`.
func minBatchNanoseconds(batches: Int = 7, over count: Int, _ body: () async -> Void) async -> Double {
    var best = Double.infinity
    for _ in 0..<batches { best = min(best, await averageNanoseconds(over: count, body)) }
    return best
}

/// Loose catastrophic-regression guard asserting `body` averages under `maxMicroseconds` per call.
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

/// Async counterpart of the synchronous `assertFast`.
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

/// Asserts `wrapped` costs at most `maxOverhead`× `raw`, using batch minimums to resist parallel-test noise.
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

/// Async counterpart with looser defaults, since actor scheduling is more sensitive to test contention.
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
