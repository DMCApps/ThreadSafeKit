// Per-operation cost of ThreadSafeKit vs. the raw stdlib type it wraps, compared against the
// previous run.
//
//     swift run -c release ThreadSafeKitBenchmarks [--runs <n>] [--output <path>] [--baseline <path>]
//                                                  [--threshold <percent>] [--strict]
//
//     --runs <n>             Repeat the whole suite n times and report the median (default: 5).
//     --output <path>        Also write the report to <path> (Markdown) and its raw numbers to the
//                            same path with a .json extension. The committed copies are
//                            Benchmarks/RESULTS.md and Benchmarks/RESULTS.json.
//     --readme <path>        Also replace the section between `<!-- BENCHMARKS:START -->` and
//                            `<!-- BENCHMARKS:END -->` in <path> (the README) with the results table.
//     --baseline <path>      Previous run to compare against (default: Benchmarks/RESULTS.json).
//     --render <path>        Don't run anything: rewrite the --readme section from a saved results
//                            file, e.g. `--render Benchmarks/RESULTS.json --readme README.md`.
//     --threshold <percent>  Deviation that gets flagged (default: 30).
//     --strict               Exit with status 1 if any column is flagged SLOWER.
//
// Each figure is the median across runs of the minimum per-call average over several batches:
// the in-run minimum filters out batches inflated by preemption, and the median across whole runs
// ignores an outlier run without having to pick a cutoff. There's no absolute pass/fail: a change is flagged when a column moves
// more than the threshold (and more than a few ns) against the baseline, so it can be investigated.
// Baselines are only compared when they came from the same machine and CPU.

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

// MARK: - Comparison

/// A column is flagged when it moves more than `threshold` percent against the baseline...
let defaultThresholdPercent = 30.0
/// ...and by more than this many ns, so tiny figures don't get flagged for sub-ns jitter.
let minimumDeltaNs = 5.0

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

// MARK: - Results

struct Row: Codable {
    let operation: String
    let raw: Double?
    let actor: Double?
    let lock: Double?
    let readerWriterLock: Double?
    let contended: Bool
    /// Largest run-to-run spread, (max − min) / median in percent, across the compared columns.
    /// How much of a baseline change could just be noise. Nil for a single run.
    var spreadPercent: Double? = nil
}

func median(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    let middle = sorted.count / 2
    return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
}

/// Combines the same row from several runs into one: each figure is the median across runs.
func combine(_ runs: [Row]) -> Row {
    let first = runs[0]
    func medianOf(_ keyPath: KeyPath<Row, Double?>) -> Double? {
        let values = runs.compactMap { $0[keyPath: keyPath] }
        return values.isEmpty ? nil : median(values)
    }
    var spread: Double?
    if runs.count > 1 {
        spread = comparedColumns.compactMap { column -> Double? in
            let values = runs.compactMap { $0[keyPath: column.keyPath] }
            guard let low = values.min(), let high = values.max() else { return nil }
            let middle = median(values)
            return middle > 0 ? (high - low) / middle * 100 : nil
        }.max()
    }
    return Row(
        operation: first.operation,
        raw: medianOf(\.raw),
        actor: medianOf(\.actor),
        lock: medianOf(\.lock),
        readerWriterLock: medianOf(\.readerWriterLock),
        contended: first.contended,
        spreadPercent: spread
    )
}

struct SystemInfo: Codable, Equatable {
    let date: String
    let machine: String
    let cpu: String
    let cores: String
    let memory: String
    let os: String
    let compiler: String

    /// Whether numbers from `other` can be meaningfully compared with numbers from this system.
    func isComparable(with other: SystemInfo) -> Bool {
        machine == other.machine && cpu == other.cpu
    }
}

/// One run: what the JSON file holds, and what the next run compares against.
struct Snapshot: Codable {
    let system: SystemInfo
    let rows: [Row]
    /// How many whole-suite runs each median came from.
    var runs: Int? = nil
}

/// The columns compared against the baseline. Raw isn't one: it measures the stdlib, not this
/// library, so it's shown for context only.
let comparedColumns: [(name: String, keyPath: KeyPath<Row, Double?> & Sendable)] = [
    ("actor", \.actor),
    (".lock", \.lock),
    (".readerWriterLock", \.readerWriterLock),
]

func percentChange(_ current: Double, from previous: Double) -> Double {
    (current - previous) / previous * 100
}

/// "SLOWER"/"FASTER" flags for `row` against `previous`; empty when nothing moved enough. A change
/// must exceed the threshold, the two runs' combined run-to-run spread (so a noisy baseline row
/// doesn't produce a false flag), and `minimumDeltaNs`.
func flags(for row: Row, against previous: Row, thresholdPercent: Double) -> (slower: [String], faster: [String]) {
    var slower: [String] = []
    var faster: [String] = []
    let noisePercent = (row.spreadPercent ?? 0) + (previous.spreadPercent ?? 0)
    for column in comparedColumns {
        guard let now = row[keyPath: column.keyPath], let before = previous[keyPath: column.keyPath], before > 0 else { continue }
        let change = percentChange(now, from: before)
        guard abs(change) > max(thresholdPercent, noisePercent), abs(now - before) > minimumDeltaNs else { continue }
        let text = "\(column.name) \(String(format: "%+.0f%%", change))"
        if change > 0 { slower.append(text) } else { faster.append(text) }
    }
    return (slower, faster)
}

/// `rows` as a Markdown table: readable in a terminal, and by agents via `--output`. With a
/// baseline, each figure shows its change and the last column says whether anything moved.
func markdownTable(_ rows: [Row], baseline: [String: Row]?, thresholdPercent: Double) -> String {
    let headers = ["Operation", "Raw", "actor", ".lock", ".readerWriterLock", "Spread"] + (baseline == nil ? [] : ["vs. baseline"])
    func cell(_ value: Double?, _ previous: Double?) -> String {
        guard let value else { return "-" }
        let figure = String(format: "%.1f", value)
        guard let previous, previous > 0 else { return figure }
        return figure + " (" + String(format: "%+.0f%%", percentChange(value, from: previous)) + ")"
    }
    let body: [[String]] = rows.map { row in
        let previous = baseline?[row.operation]
        var cells = [
            row.operation,
            cell(row.raw, previous?.raw),
            cell(row.actor, previous?.actor),
            cell(row.lock, previous?.lock),
            cell(row.readerWriterLock, previous?.readerWriterLock),
            row.spreadPercent.map { String(format: "±%.0f%%", $0 / 2) } ?? "-",
        ]
        if let baseline {
            if let previous = baseline[row.operation] {
                let (slower, faster) = flags(for: row, against: previous, thresholdPercent: thresholdPercent)
                var verdict: [String] = []
                if !slower.isEmpty { verdict.append("⚠️ SLOWER: " + slower.joined(separator: ", ")) }
                if !faster.isEmpty { verdict.append("FASTER: " + faster.joined(separator: ", ")) }
                cells.append(verdict.isEmpty ? "ok" : verdict.joined(separator: "; "))
            } else {
                cells.append("new")
            }
        }
        return cells
    }
    let widths = headers.indices.map { column in
        ([headers[column]] + body.map { $0[column] }).map(\.count).max()!
    }
    // Operation and verdict columns are left-aligned; figure columns are right-aligned.
    func isText(_ column: Int) -> Bool { column == 0 || column == 6 }
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
    var runs = 5
    var outputPath: String?
    var readmePath: String?
    var renderPath: String?
    var baselinePath = "Benchmarks/RESULTS.json"
    var thresholdPercent = defaultThresholdPercent
    var strict = false

    init(_ arguments: [String]) {
        var remaining = arguments.dropFirst()
        func value(for flag: String) -> String {
            guard let value = remaining.popFirst() else { Self.usage("\(flag) needs a value") }
            return value
        }
        while let argument = remaining.popFirst() {
            switch argument {
            case "--runs":
                guard let count = Int(value(for: argument)), count > 0 else { Self.usage("--runs needs a positive integer") }
                runs = count
            case "--output": outputPath = value(for: argument)
            case "--readme": readmePath = value(for: argument)
            case "--render": renderPath = value(for: argument)
            case "--baseline": baselinePath = value(for: argument)
            case "--threshold":
                guard let percent = Double(value(for: argument)), percent > 0 else { Self.usage("--threshold needs a positive number") }
                thresholdPercent = percent
            case "--strict": strict = true
            default: Self.usage("unknown argument '\(argument)'")
            }
        }
    }

    static func usage(_ problem: String) -> Never {
        print("""
        ThreadSafeKitBenchmarks: \(problem)
        usage: ThreadSafeKitBenchmarks [--runs <n>] [--output <path>] [--readme <path>] [--render <path>] [--baseline <path>] [--threshold <percent>] [--strict]
        """)
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
/// type), so baselines are only compared when they came from the same machine and CPU.
func currentSystem() -> SystemInfo {
    let info = ProcessInfo.processInfo
    let performanceCores = sysctlInt("hw.perflevel0.physicalcpu")
    let efficiencyCores = sysctlInt("hw.perflevel1.physicalcpu")
    let coreSplit = [performanceCores.map { "\($0) performance" }, efficiencyCores.map { "\($0) efficiency" }]
        .compactMap { $0 }.joined(separator: " + ")
    return SystemInfo(
        date: ISO8601DateFormatter().string(from: Date()),
        machine: sysctlString("hw.model") ?? "unknown",
        cpu: sysctlString("machdep.cpu.brand_string") ?? "unknown",
        cores: "\(info.activeProcessorCount) active" + (coreSplit.isEmpty ? "" : " (\(coreSplit))"),
        memory: sysctlInt("hw.memsize").map { "\($0 / 1_073_741_824) GB" } ?? "unknown",
        os: "macOS \(info.operatingSystemVersionString)",
        compiler: compilerVersion() + ", release build"
    )
}

func systemTable(_ system: SystemInfo) -> String {
    let fields = [
        ("Date", system.date), ("Machine", system.machine), ("CPU", system.cpu), ("Cores", system.cores),
        ("Memory", system.memory), ("OS", system.os), ("Compiler", system.compiler),
    ]
    return (["| | |", "| --- | --- |"] + fields.map { "| \($0.0) | \($0.1) |" }).joined(separator: "\n")
}

let options = Options(CommandLine.arguments)

if let renderPath = options.renderPath {
    guard let readmePath = options.readmePath else { Options.usage("--render needs --readme <path>") }
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: renderPath)),
          let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
    else {
        print("ThreadSafeKitBenchmarks: couldn't read results from \(renderPath)")
        exit(2)
    }
    updateReadme(at: readmePath, rows: snapshot.rows, system: snapshot.system, runs: snapshot.runs ?? options.runs)
    exit(0)
}

let system = currentSystem()

// Load the baseline before running, so `--output` can overwrite the same file afterwards.
let baselineSnapshot: Snapshot? = (try? Data(contentsOf: URL(fileURLWithPath: options.baselinePath)))
    .flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
let comparableBaseline = baselineSnapshot.flatMap { $0.system.isComparable(with: system) ? $0 : nil }
let baselineNote: String
switch (baselineSnapshot, comparableBaseline) {
case (nil, _):
    baselineNote = "No baseline found at `\(options.baselinePath)`, so there's nothing to compare against yet."
case (let snapshot?, nil):
    baselineNote = "Baseline `\(options.baselinePath)` is from a different system (\(snapshot.system.machine), \(snapshot.system.cpu)), so it isn't compared. Numbers are only comparable on the same machine."
case (_, let snapshot?):
    baselineNote = "Compared with `\(options.baselinePath)` from \(snapshot.system.date). Percentages are the change from that run. Anything flagged moved more than \(Int(options.thresholdPercent))%, beyond both runs' noise, and by more than \(Int(minimumDeltaNs)) ns: investigate it before accepting the new numbers."
}

print("Running ThreadSafeKit benchmarks: \(options.runs) run(s), ~20 seconds each…")
var runs: [[Row]] = []
for run in 1...options.runs {
    runs.append(await runBenchmarks())
    print("  run \(run)/\(options.runs) done")
}
let rows = runs[0].indices.map { index in combine(runs.map { $0[index] }) }
let baselineRows = comparableBaseline.map { Dictionary($0.rows.map { ($0.operation, $0) }, uniquingKeysWith: { first, _ in first }) }
let slowerCount = baselineRows.map { previous in
    rows.filter { row in previous[row.operation].map { !flags(for: row, against: $0, thresholdPercent: options.thresholdPercent).slower.isEmpty } ?? false }.count
} ?? 0

let report = """
# ThreadSafeKit benchmarks

Regenerate (and update the baseline and README): `swift run -c release ThreadSafeKitBenchmarks --output Benchmarks/RESULTS.md --readme README.md`

## Results

\(baselineNote)

\(markdownTable(rows, baseline: baselineRows, thresholdPercent: options.thresholdPercent))
\(baselineRows == nil ? "" : "\n**\(slowerCount) of \(rows.count) operations flagged slower.**\n")
### Legend

- **Units:** every figure is **nanoseconds per operation (ns/op)**. Lower is better. 1,000 ns = 1 µs.
- **Raw:** the unsynchronized stdlib type (`Array`/`Dictionary`/`Set`/`Int`) on a single thread. Context for what the wrapper adds; not compared against the baseline.
- **actor:** the actor type (`ThreadSafeArray`/`ThreadSafeDictionary`/`ThreadSafeSet`/`ThreadSafeAtomic`), called with `await`. Where it has no direct equivalent it uses the closest API (`a[i] = v` → `setElement`, `+=` → `mutate`, `d[k] = v` → `updateValue`).
- **.lock / .readerWriterLock:** `ThreadSafe<Value>` with that `ThreadSafeMechanism`.
- **Contended rows:** \(contendedWorkers) concurrent workers on one shared instance, reported as wall-clock ns per operation. No Raw figure: unsynchronized concurrent access to the raw type would be a data race.
- **How each figure is measured:** the median of \(options.runs) whole-suite run(s). Within a run, it's the fastest per-call average over \(batches) batches, which filters out batches slowed by preemption; the median across runs then ignores an outlier run.
- **Spread:** the largest run-to-run variation in the row (± half of max − min, as a % of the median). A baseline change within that range is likely noise.
- **(+n%) / (−n%):** change from the baseline run. Positive = slower.
- **vs. baseline:** `ok` = nothing moved enough to flag; `⚠️ SLOWER` / `FASTER` = a column moved more than \(Int(options.thresholdPercent))%, more than the two runs' combined spread, **and** more than \(Int(minimumDeltaNs)) ns; `new` = no baseline figure for this operation. Investigate a ⚠️ before accepting the new numbers. If the change is expected, regenerate with `--output` and commit the results as the new baseline.

## System

\(systemTable(system))

"""

print("\n" + report)

if let path = options.outputPath {
    let markdownURL = URL(fileURLWithPath: path)
    let jsonURL = markdownURL.deletingPathExtension().appendingPathExtension("json")
    do {
        try FileManager.default.createDirectory(at: markdownURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try report.write(to: markdownURL, atomically: true, encoding: .utf8)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Snapshot(system: system, rows: rows, runs: options.runs)).write(to: jsonURL, options: .atomic)
        print("Wrote \(markdownURL.path) and \(jsonURL.path)")
    } catch {
        print("ThreadSafeKitBenchmarks: couldn't write results: \(error)")
        exit(2)
    }
}

/// The README copy: the table without baseline deltas, plus a short legend. GitHub Markdown can't
/// include another file, so the section between the markers is regenerated in place instead.
func updateReadme(at path: String, rows: [Row], system: SystemInfo, runs: Int) {
    let startMarker = "<!-- BENCHMARKS:START -->"
    let endMarker = "<!-- BENCHMARKS:END -->"
    guard let readme = try? String(contentsOfFile: path, encoding: .utf8),
          let start = readme.range(of: startMarker), let end = readme.range(of: endMarker),
          start.upperBound <= end.lowerBound
    else {
        print("ThreadSafeKitBenchmarks: couldn't find \(startMarker) … \(endMarker) in \(path)")
        exit(2)
    }
    let section = """

    <!-- Generated by ThreadSafeKitBenchmarks (--readme); edits between these markers are overwritten. -->

    \(markdownTable(rows, baseline: nil, thresholdPercent: options.thresholdPercent))

    Nanoseconds per operation (ns/op), lower is better; median of \(runs) runs. **Raw** is the unsynchronized stdlib type on one thread; **actor** is the actor type (`ThreadSafeArray`/…); **.lock** / **.readerWriterLock** are `ThreadSafe<Value>` with that mechanism; **Spread** is run-to-run variation. Contended rows are \(contendedWorkers) concurrent workers on one instance (no Raw figure: that would be a data race). Measured on \(system.cpu) (\(system.machine)), \(system.os), \(system.date). Numbers are only comparable on the same machine. Full legend and baseline comparison: [Benchmarks/RESULTS.md](Benchmarks/RESULTS.md).

    """
    let updated = readme.replacingCharacters(in: start.upperBound..<end.lowerBound, with: section)
    do {
        try updated.write(toFile: path, atomically: true, encoding: .utf8)
        print("Updated benchmarks section in \(path)")
    } catch {
        print("ThreadSafeKitBenchmarks: couldn't write \(path): \(error)")
        exit(2)
    }
}

if let path = options.readmePath {
    updateReadme(at: path, rows: rows, system: system, runs: options.runs)
}

if options.strict && slowerCount > 0 {
    exit(1)
}
