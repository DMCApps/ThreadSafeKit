import Foundation
import Testing

let concurrencyIterations = 2000

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
