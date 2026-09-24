// Per-operation cost of ThreadSafeKit vs. the raw stdlib type it wraps.
//
//     swift run -c release ThreadSafeKitBenchmarks [--output <path>] [--strict]
//
//     --output <path>  Also write the report (Markdown) to <path>. The committed copy lives at
//                      Benchmarks/RESULTS.md: regenerate it with
//                      `swift run -c release ThreadSafeKitBenchmarks --output Benchmarks/RESULTS.md`.
//     --strict         Exit with status 1 if any row FAILs (default: always exit 0).
//
// Prints one table: each operation's cost on the raw type (unsynchronized, single thread), the
// actor type, and `ThreadSafe` under each mechanism, plus PASS/FAIL against the criteria below.
// The test suite's performance tests are regression guards that have to survive debug builds,
// parallel tests, and TSan; this is where real numbers come from. Each figure is the minimum
// per-call average over several batches, which filters out batches inflated by preemption.

import Dispatch
import Foundation
import os
import ThreadSafeKit

/// Exits in debug builds. A function (not top-level `#if DEBUG ... exit`) so the code below
/// isn't flagged as unreachable when building debug, e.g. via `swift build --build-tests`.
func refuseDebugBuild() {
    #if DEBUG
    print("ThreadSafeKitBenchmarks: build with `-c release` — debug numbers are meaningless.")
    exit(1)
    #endif
}
refuseDebugBuild()

// MARK: - Criteria

/// Single-thread rows: each wrapped column must cost at most `max(raw × ratio, floor)`. The floor
/// stops a near-zero raw cost from making the ratio impossible to meet.
let syncMaxRatio = 25.0
let syncFloorNs = 100.0
/// The actor column gets a looser budget: every call is an `await` into another isolation domain.
let actorMaxRatio = 50.0
let actorFloorNs = 250.0
/// Contended rows have no raw baseline (unsynchronized concurrent access to the raw type is a
/// data race), so they're held to an absolute wall-clock ceiling per operation instead.
let contendedCeilingNs = 1_000.0

// MARK: - Harness

/// Keeps `value` alive so the optimizer can't delete the work that produced it.
@inline(never) @_optimize(none)
func blackHole<T>(_ value: T) {}

/// Hides `value` from the optimizer, so work on it can't be hoisted out of the timing loop.
/// Without this, raw reads like `array.count` get hoisted and measure as ~0 ns. `@_optimize(none)`
/// stops the optimizer from proving this is an identity function and seeing through the call.
@inline(never) @_optimize(none)
func opaque<T>(_ value: T) -> T { value }

let batches = 7
let singleThreadOps = 500_000
let actorOps = 100_000
let contendedWorkers = 8
let contendedOpsPerWorker = 100_000

/// Minimum average ns/op across `batches` batches of `ops` calls.
func measure(ops: Int = singleThreadOps, _ body: () -> Void) -> Double {
    var best = Double.infinity
    for _ in 0..<batches {
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<ops { body() }
        best = min(best, Double(DispatchTime.now().uptimeNanoseconds - start) / Double(ops))
    }
    return best
}

/// Async counterpart of `measure`, for the actor types.
func measure(ops: Int = actorOps, _ body: () async -> Void) async -> Double {
    var best = Double.infinity
    for _ in 0..<batches {
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<ops { await body() }
        best = min(best, Double(DispatchTime.now().uptimeNanoseconds - start) / Double(ops))
    }
    return best
}

/// Wall-clock ns per operation (total time / total ops) with `contendedWorkers` threads each
/// calling `body(iteration)`. Minimum over a few runs.
func measureContended(_ body: @Sendable @escaping (Int) -> Void) -> Double {
    var best = Double.infinity
    for _ in 0..<3 {
        let start = DispatchTime.now().uptimeNanoseconds
        DispatchQueue.concurrentPerform(iterations: contendedWorkers) { _ in
            for i in 0..<contendedOpsPerWorker { body(i) }
        }
        let total = Double(contendedWorkers * contendedOpsPerWorker)
        best = min(best, Double(DispatchTime.now().uptimeNanoseconds - start) / total)
    }
    return best
}

/// Actor counterpart of `measureContended`: `contendedWorkers` concurrent tasks, each doing a
/// tenth of the synchronous per-worker count (actor calls are slower, so this keeps runtime sane).
func measureContended(_ body: @Sendable @escaping (Int) async -> Void) async -> Double {
    let opsPerWorker = contendedOpsPerWorker / 10
    var best = Double.infinity
    for _ in 0..<3 {
        let start = DispatchTime.now().uptimeNanoseconds
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<contendedWorkers {
                group.addTask { for i in 0..<opsPerWorker { await body(i) } }
            }
        }
        let total = Double(contendedWorkers * opsPerWorker)
        best = min(best, Double(DispatchTime.now().uptimeNanoseconds - start) / total)
    }
    return best
}

// MARK: - Table

struct Row {
    let operation: String
    let raw: Double?
    let actor: Double?
    let lock: Double?
    let readerWriterLock: Double?
    let contended: Bool

    /// Names of the columns that miss their budget; empty means PASS.
    var failures: [String] {
        func over(_ value: Double?, ratio: Double, floor: Double) -> Bool {
            guard let value else { return false }
            if contended { return value > contendedCeilingNs }
            guard let raw else { return false }
            return value > max(raw * ratio, floor)
        }
        var names: [String] = []
        if over(actor, ratio: actorMaxRatio, floor: actorFloorNs) { names.append("actor") }
        if over(lock, ratio: syncMaxRatio, floor: syncFloorNs) { names.append(".lock") }
        if over(readerWriterLock, ratio: syncMaxRatio, floor: syncFloorNs) { names.append(".readerWriterLock") }
        return names
    }
}

/// `rows` as a Markdown table: readable in a terminal, and by agents via `--output`.
func markdownTable(_ rows: [Row]) -> String {
    let headers = ["Operation", "Raw", "actor", ".lock", ".readerWriterLock", "Result"]
    func cell(_ value: Double?) -> String { value.map { String(format: "%.1f", $0) } ?? "-" }
    let body: [[String]] = rows.map { row in
        let failures = row.failures
        let result = failures.isEmpty ? "PASS" : "FAIL (\(failures.joined(separator: ", ")))"
        return [row.operation, cell(row.raw), cell(row.actor), cell(row.lock), cell(row.readerWriterLock), result]
    }
    let widths = headers.indices.map { column in
        ([headers[column]] + body.map { $0[column] }).map(\.count).max()!
    }
    // Text columns (first and last) are left-aligned; number columns are right-aligned.
    func isText(_ column: Int) -> Bool { column == 0 || column == headers.count - 1 }
    func line(_ cells: [String]) -> String {
        let padded = cells.enumerated().map { column, text in
            let padding = String(repeating: " ", count: widths[column] - text.count)
            return isText(column) ? text + padding : padding + text
        }
        return "| " + padded.joined(separator: " | ") + " |"
    }
    let separator = widths.indices.map { column in
        isText(column) ? String(repeating: "-", count: widths[column]) : String(repeating: "-", count: widths[column] - 1) + ":"
    }
    return ([line(headers), line(separator)] + body.map(line)).joined(separator: "\n")
}

// MARK: - Benchmarks

let mechanisms: [ThreadSafeMechanism] = [.lock, .readerWriterLock]

// Wrapped in a function: top-level `main.swift` globals are main-actor isolated, and sending a
// closure from that context into an actor method trips region-isolation checking. Ordinary
// `@MainActor` functions don't hit this; it's specific to top-level script code.
func runBenchmarks() async -> [Row] {
    var rows: [Row] = []
    func add(_ operation: String, raw: Double?, actor: Double?, wrapped: [Double], contended: Bool = false) {
        rows.append(Row(operation: operation, raw: raw, actor: actor, lock: wrapped[0], readerWriterLock: wrapped[1], contended: contended))
    }

    // Array
    do {
        var raw = Array(0..<64)
        let actor = ThreadSafeArray(Array(0..<64))
        let wrapped = mechanisms.map { ThreadSafe(Array(0..<64), mechanism: $0) }
        add("Array count",
            raw: measure { blackHole(opaque(raw).count) },
            actor: await measure { blackHole(await actor.count) },
            wrapped: wrapped.map { a in measure { blackHole(a.count) } })
        add("Array a[i] get",
            raw: measure { blackHole(opaque(raw)[3]) },
            actor: await measure { blackHole(await actor[3]) },
            wrapped: wrapped.map { a in measure { blackHole(a[3]) } })
        add("Array a[i] = v",
            raw: measure { raw[opaque(3)] = 1 },
            actor: await measure { await actor.setElement(1, at: 3) },
            wrapped: wrapped.map { a in measure { a[3] = 1 } })
        add("Array a[i] += 1",
            raw: measure { raw[opaque(3)] += 1 },
            actor: await measure { await actor.mutate { $0[3] += 1 } },
            wrapped: wrapped.map { a in measure { a[3] += 1 } })
        add("Array append + popLast",
            raw: measure { raw.append(opaque(1)); blackHole(raw.popLast()) },
            actor: await measure { await actor.append(1); blackHole(await actor.popLast()) },
            wrapped: wrapped.map { a in measure { a.append(1); blackHole(a.popLast()) } })
        blackHole(raw)
    }

    // Dictionary
    do {
        let seed = Dictionary(uniqueKeysWithValues: (0..<64).map { ($0, $0) })
        var raw = seed
        let actor = ThreadSafeDictionary(seed)
        let wrapped = mechanisms.map { ThreadSafe(seed, mechanism: $0) }
        add("Dictionary d[k] get",
            raw: measure { blackHole(opaque(raw)[3]) },
            actor: await measure { blackHole(await actor[3]) },
            wrapped: wrapped.map { d in measure { blackHole(d[3]) } })
        add("Dictionary d[k] = v",
            raw: measure { raw[opaque(3)] = 1 },
            actor: await measure { _ = await actor.updateValue(1, forKey: 3) },
            wrapped: wrapped.map { d in measure { d[3] = 1 } })
        add("Dictionary d[k]! += 1",
            raw: measure { raw[opaque(3)]! += 1 },
            actor: await measure { await actor.mutate { $0[3]! += 1 } },
            wrapped: wrapped.map { d in measure { d[3]! += 1 } })
        add("Dictionary updateValue",
            raw: measure { blackHole(raw.updateValue(1, forKey: opaque(3))) },
            actor: await measure { blackHole(await actor.updateValue(1, forKey: 3)) },
            wrapped: wrapped.map { d in measure { blackHole(d.updateValue(1, forKey: 3)) } })
        blackHole(raw)
    }

    // Set
    do {
        var raw = Set(0..<64)
        let actor = ThreadSafeSet(Set(0..<64))
        let wrapped = mechanisms.map { ThreadSafe(Set(0..<64), mechanism: $0) }
        add("Set contains",
            raw: measure { blackHole(opaque(raw).contains(3)) },
            actor: await measure { blackHole(await actor.contains(3)) },
            wrapped: wrapped.map { s in measure { blackHole(s.contains(3)) } })
        add("Set insert + remove",
            raw: measure { raw.insert(opaque(999)); raw.remove(999) },
            actor: await measure { await actor.insert(999); _ = await actor.remove(999) },
            wrapped: wrapped.map { s in measure { s.insert(999); s.remove(999) } })
        blackHole(raw)
    }

    // Scalar: ThreadSafe<Int> vs. ThreadSafeAtomic<Int>
    do {
        var raw = 0
        let actor = ThreadSafeAtomic(0)
        let wrapped = mechanisms.map { ThreadSafe(wrappedValue: 0, mechanism: $0) }
        add("Scalar read",
            raw: measure { blackHole(opaque(raw)) },
            actor: await measure { blackHole(await actor.get()) },
            wrapped: wrapped.map { c in measure { blackHole(c.wrappedValue) } })
        add("Scalar mutate { += 1 }",
            raw: measure { raw += opaque(1) },
            actor: await measure { await actor.mutate { $0 += 1 } },
            wrapped: wrapped.map { c in measure { c.mutate { $0 += 1 } } })
        blackHole(raw)
    }

    // Contended: 8 concurrent workers on one shared instance.
    do {
        let actor = ThreadSafeArray(Array(0..<64))
        let readHeavyActor = await measureContended { i in
            if i % 10 == 0 { await actor.setElement(i, at: i & 63) } else { blackHole(await actor.count) }
        }
        add("Contended 90% read / 10% write",
            raw: nil, actor: readHeavyActor,
            wrapped: mechanisms.map { m in
                let a = ThreadSafe(Array(0..<64), mechanism: m)
                return measureContended { i in if i % 10 == 0 { a[i & 63] = i } else { blackHole(a.count) } }
            },
            contended: true)
        let readOnlyActor = await measureContended { i in blackHole(await actor[i & 63]) }
        add("Contended 100% read",
            raw: nil, actor: readOnlyActor,
            wrapped: mechanisms.map { m in
                let a = ThreadSafe(Array(0..<64), mechanism: m)
                return measureContended { i in blackHole(a[i & 63]) }
            },
            contended: true)
        let writeOnlyActor = await measureContended { i in await actor.mutate { $0[i & 63] += 1 } }
        add("Contended 100% write (a[i] += 1)",
            raw: nil, actor: writeOnlyActor,
            wrapped: mechanisms.map { m in
                let a = ThreadSafe(Array(0..<64), mechanism: m)
                return measureContended { i in a[i & 63] += 1 }
            },
            contended: true)
    }
    return rows
}

// MARK: - Report

struct Options {
    var outputPath: String?
    var strict = false

    init(_ arguments: [String]) {
        var remaining = arguments.dropFirst()
        while let argument = remaining.popFirst() {
            switch argument {
            case "--output":
                guard let path = remaining.popFirst() else { Self.usage("--output needs a path") }
                outputPath = path
            case "--strict":
                strict = true
            default:
                Self.usage("unknown argument '\(argument)'")
            }
        }
    }

    static func usage(_ problem: String) -> Never {
        print("ThreadSafeKitBenchmarks: \(problem)\nusage: ThreadSafeKitBenchmarks [--output <path>] [--strict]")
        exit(2)
    }
}

func sysctlString(_ name: String) -> String? {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
    var buffer = [UInt8](repeating: 0, count: size)
    guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
    return String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
}

func sysctlInt(_ name: String) -> Int? {
    var value: Int64 = 0
    var size = MemoryLayout<Int64>.size
    guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
    return Int(value)
}

/// Compiler that built this binary, to the nearest minor version.
func compilerVersion() -> String {
    #if compiler(>=6.5)
    return "Swift 6.5 or later"
    #elseif compiler(>=6.4)
    return "Swift 6.4"
    #elseif compiler(>=6.3)
    return "Swift 6.3"
    #else
    return "Swift earlier than 6.3"
    #endif
}

/// The system the numbers came from. Results depend heavily on the machine (CPU, core count and
/// type), so they're only comparable between runs on the same system.
func systemTable() -> String {
    let info = ProcessInfo.processInfo
    let performanceCores = sysctlInt("hw.perflevel0.physicalcpu")
    let efficiencyCores = sysctlInt("hw.perflevel1.physicalcpu")
    let coreSplit = [performanceCores.map { "\($0) performance" }, efficiencyCores.map { "\($0) efficiency" }]
        .compactMap { $0 }.joined(separator: " + ")
    let memoryGB = sysctlInt("hw.memsize").map { "\($0 / 1_073_741_824) GB" } ?? "unknown"
    let fields: [(String, String)] = [
        ("Date", ISO8601DateFormatter().string(from: Date())),
        ("Machine", sysctlString("hw.model") ?? "unknown"),
        ("CPU", sysctlString("machdep.cpu.brand_string") ?? "unknown"),
        ("Cores", "\(info.activeProcessorCount) active" + (coreSplit.isEmpty ? "" : " (\(coreSplit))")),
        ("Memory", memoryGB),
        ("OS", "macOS \(info.operatingSystemVersionString)"),
        ("Compiler", compilerVersion() + ", release build"),
    ]
    return (["| | |", "| --- | --- |"] + fields.map { "| \($0.0) | \($0.1) |" }).joined(separator: "\n")
}

let options = Options(CommandLine.arguments)
print("Running ThreadSafeKit benchmarks (release build, ~1 minute)…")
let rows = await runBenchmarks()
let failed = rows.filter { !$0.failures.isEmpty }.count

let report = """
# ThreadSafeKit benchmarks

ns/op, lower is better; each figure is the minimum per-call average over \(batches) batches.
Numbers are only comparable between runs on the same machine.

Regenerate: `swift run -c release ThreadSafeKitBenchmarks --output Benchmarks/RESULTS.md`

## Results

\(markdownTable(rows))

**\(rows.count - failed)/\(rows.count) PASS**

## System

Numbers depend heavily on the machine, so compare them only against runs on the same system.

\(systemTable())

## Criteria

- **Raw** is the unsynchronized stdlib type (`Array`/`Dictionary`/`Set`/`Int`) on a single thread.
- **Single-thread:** `.lock` / `.readerWriterLock` ≤ max(Raw × \(Int(syncMaxRatio)), \(Int(syncFloorNs)) ns); actor ≤ max(Raw × \(Int(actorMaxRatio)), \(Int(actorFloorNs)) ns).
- **Contended:** every column ≤ \(Int(contendedCeilingNs)) ns/op wall-clock with \(contendedWorkers) concurrent workers. No Raw baseline: unsynchronized concurrent access to the raw type would be a data race.
- The actor column uses the actor's equivalent API where there's no direct one (`a[i] = v` → `setElement`, `+=` → `mutate`, `d[k] = v` → `updateValue`).

"""

print("\n" + report)

if let path = options.outputPath {
    do {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try report.write(to: url, atomically: true, encoding: .utf8)
        print("Wrote \(path)")
    } catch {
        print("ThreadSafeKitBenchmarks: couldn't write \(path): \(error)")
        exit(2)
    }
}

if options.strict && failed > 0 {
    exit(1)
}
