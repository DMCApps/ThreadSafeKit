# ThreadSafeKit

Thread-safe wrappers that make threading easier on iOS, tvOS and macOS under Swift 6 strict concurrency. `async`/`await` can't be used everywhere, so `@ThreadSafe` gives ordinary values actor-style safety without `await`. You use the wrapped `Array`, `Dictionary`, `Set` or value as you normally would, and every read and write is atomic. When callers can `await`, the actor types offer the same API. Every type is `Sendable`, so shared mutable state can cross isolation domains with no locking at the call site.

Thread safety and speed are the library's top priorities: every operation is atomic, and each one costs as close to the raw stdlib call as the lock allows (see [Benchmarks](#benchmarks)).

**Latest benchmarks:** [Benchmarks/RESULTS.md](Benchmarks/RESULTS.md): per-operation cost of each type and mechanism against the raw stdlib type, with the system they were measured on.

## Requirements

- Swift 6.3+ tools, `swiftLanguageModes: [.v6]`
- iOS 17+, tvOS 17+, macOS 14+

## Install

```swift
.package(url: "https://github.com/DMCApps/ThreadSafeKit.git", branch: "main")
```

## Usage

```swift
@ThreadSafe var counter = 0
_counter.mutate { $0 += 1 }

@ThreadSafe var items = [1, 2, 3]
$items.append(4)   // items == [1, 2, 3, 4]

@ThreadSafe(mechanism: .readerWriterLock) var cache = ["key": 1]
$cache["other"] = 2   // cache == ["key": 1, "other": 2]

let list = ThreadSafeArray<Int>()
await list.append(1)
let all = await list.elements
```

`ThreadSafe<Value>` also works as a plain instance (`let list = ThreadSafe<[Int]>()`) when you don't want property-wrapper sugar.

In a `Sendable` class, use the plain-instance form as a `let` — `@ThreadSafe var` won't compile there, because the wrapper's generated storage (`_items`) is a `var`:

```swift
final class Store: Sendable {
    let items = ThreadSafe<[Int]>()   // not `@ThreadSafe var items: [Int] = []`
}
```

### Subscripts are atomic

`ts[i] += 1`, `dict[k]! += 1`, `dict[k]?.append(x)`, and plain `ts[i] = v`/`dict[k] = v` are each a single atomic access — the write lock is held across the entire get-modify-set, so concurrent compound assignment through a subscript can't lose updates. `ts[i] = ts[i] + 1`, however, is *two* separate accesses (a read, then a separate write), so it is **not** atomic — the two accesses can interleave with another caller's write in between. Use `+=` (or `mutate`, below) for anything that needs to be a single step.

Never pass a subscript `inout` to an `async` function (`await someAsyncFunc(&ts[i])`) — it compiles, but it holds the write lock across the `await`. If the task resumes on a different thread, it traps; if it resumes on the same thread (e.g. `@MainActor`), nothing traps, but the lock stays held for the whole `await`, blocking every other access to that instance and making any reentrant access from that same thread trap. Copy the value out, `await`, then write back instead:

```swift
// NOT safe: holds the write lock across the suspension point
await someAsyncFunc(&ts[i])

// OK: the lock is only held for the read and the write, not the await
var value = ts[i]
await someAsyncFunc(&value)
ts[i] = value
```

The copy-out form is two separate accesses, so it isn't atomic across the `await`: any write another caller makes to `ts[i]` while you're suspended is overwritten by the final assignment. If that matters, re-check or merge inside a single `mutate` after the `await` instead of assigning blindly.

### Compound operations with `mutate`

Every individual call (`append`, `updateValue`, subscripts, …) is atomic on its own, but two separate calls are not atomic *together* — a read followed by a write can race with another caller's write in between:

```swift
// NOT safe: another writer can slip in between these two calls
if await dict["x"] == nil {
    await dict.updateValue(1, forKey: "x")
}
```

The same pitfall shows up as check-then-act with `firstIndex`/`remove(at:)` on an array — the index found by `firstIndex` can be stale by the time `remove(at:)` runs, if another writer mutates the array in between:

```swift
// NOT safe: the array can change between the find and the remove
if let i = list.firstIndex(of: x) {
    list.remove(at: i)
}

// Safe: `removeAll(where:)` does the find and the remove as one atomic step
list.removeAll(where: { $0 == x })
```

`mutate(_:)` holds the lock/actor across the whole closure, so a multi-step read-then-write is atomic as one unit:

```swift
await dict.mutate { storage in
    if storage["x"] == nil {
        storage["x"] = 1
    }
}

await list.mutate { elements in
    elements.append(elements.count)   // check-then-act, race-free
}

let counter = ThreadSafe(wrappedValue: 0)
counter.mutate { $0 += 1 }   // ThreadSafe already works this way, regardless of mechanism
```

`mutate` also returns whatever `body` returns, so a compound read-and-update — the most common reason to reach for an atomic — is a single call:

```swift
let idGenerator = ThreadSafeAtomic(0)
let nextID = await idGenerator.mutate { value in
    defer { value += 1 }
    return value
}
```

**Don't call back into the same instance, and don't nest two instances in opposite orders.** Inside a `mutate` (or `forEach`/`map`/`removeAll(where:)`/… closure), touching the *same* `ThreadSafe` instance traps immediately. Nesting a *different* instance works (`a.mutate { _ in b.mutate { … } }`), but if one thread nests `a` → `b` while another nests `b` → `a`, each holds one lock and waits for the other, and both hang forever with no trap. Avoid nesting different instances; if you must, always nest them in the same order, or snapshot one first (`let bValue = b.wrappedValue`) and then `mutate` the other. The actor types can't deadlock this way: their `mutate` closure is synchronous, so it can't `await` another actor.

**What this does and doesn't fix.** Every type here is already fully thread-safe — no data races, no memory corruption, no crashes, on any single call, with or without `mutate`. The bug `mutate` fixes is a different, narrower one: a *logical* race (check-then-act / TOCTOU) that shows up when a correct outcome depends on two or more calls happening as one step. That race is a bug in your call sequence, not in the underlying storage — but you need `mutate` to close it, since there's no other way to hold the lock/actor across multiple steps. `mutate` doesn't add thread safety that was missing; it adds the ability to make a multi-step operation indivisible.

### Codable

The types don't conform to `Codable`. The actor types can't (encoding is synchronous, but reading actor state needs `await`), so encoding is left to you for every type: encode and decode the plain value, and wrap it yourself. That also lets you pick the mechanism:

```swift
// ThreadSafe
let items = ThreadSafe(try JSONDecoder().decode([Int].self, from: data), mechanism: .readerWriterLock)
let itemsData = try JSONEncoder().encode(items.elements)

// Actor
let list = ThreadSafeArray(try JSONDecoder().decode([Int].self, from: data))
let listData = try JSONEncoder().encode(await list.elements)
```

In a `Codable` model, store the plain value and wrap it where it's shared.

### Equatable

`ThreadSafe<Value>` is `Equatable` when `Value` is, regardless of `mechanism`:

```swift
let cache = ThreadSafe(["a": 1])
cache == ThreadSafe(["a": 1])   // true

struct Container: Equatable {
    let items: ThreadSafe<[Int]>   // synthesis works because ThreadSafe<[Int]> is itself Equatable
}
```

Not `Hashable` (see [Types](#types)). `Container` above can't add `Hashable` either, for the same
reason: its `items` field is still a mutable reference, and `let` only stops reassignment, not
mutation through it.

Actor types (`ThreadSafeArray`, `ThreadSafeDictionary`, `ThreadSafeSet`, `ThreadSafeAtomic`) aren't `Equatable` — `==` is synchronous, but reading actor-isolated state needs `await`. Compare the plain snapshots instead:

```swift
await list.elements == (await otherList.elements)
```

This also rules out `@MainActor`-style isolated conformances: that mechanism ties a conformance to one specific *global* actor, checked statically. `ThreadSafeArray<Element>`/`ThreadSafeDictionary<Key, Value>`/`ThreadSafeSet<Element>`/`ThreadSafeAtomic<Value>` are plain `actor` types — each instance is its own isolation domain, so there's no single actor to name, and it wouldn't remove the `await` for a caller outside the isolated instance anyway.

## Types

Shape-specific members mirror the standard library's own `Array`/`Dictionary`/`Set` names, so the API can be guessed from stdlib familiarity; the wrapper-only members are `mutate`, `wrappedValue`/`$name`, the snapshot accessors (`elements`/`dictionary`), `subscript(safe:)`, `ThreadSafeAtomic`'s `get()`/`set(_:)`, and the actor-only `ThreadSafeArray.setElement(_:at:)`.

One generic type, `ThreadSafe<Value>`, backs the sync API. Pick the backing mechanism via `ThreadSafeMechanism` (default `.lock`): `.lock` (`OSAllocatedUnfairLock`, every access fully exclusive — reads included) or `.readerWriterLock` (`pthread_rwlock_t`, locked manually — concurrent reads, exclusive writes). See [Which to use](#which-to-use). `ThreadSafe<Value>` itself is `@unchecked Sendable` regardless of which mechanism you pick — the choice is a runtime backing detail, not a type-level distinction, and safety is enforced internally (locking) rather than by the compiler either way.

Subscripts (`ts[i]`, `dict[k]`) are atomic for the whole access under either mechanism, including compound forms like `ts[i] += 1` and `dict[k]?.append(x)` — see [Subscripts are atomic](#subscripts-are-atomic).

### Which to use

| Choose | When | Why |
|---|---|---|
| `ThreadSafe<Value>`, `.lock` (default) | Most shared state: counters, caches, and collections read and written with short operations (`append`, subscripts, `contains`, `updateValue`, …). | Fastest for every short operation, contended or not: ~5 ns for `count` and ~47 ns for 8-way contended reads, against ~20 ns and ~340 ns for `.readerWriterLock`. |
| `ThreadSafe<Value>`, `.readerWriterLock` | Many threads reading the same large collection at once, with scans like `filter`, `map`, `sorted` or `contains(where:)` over roughly 1,000+ elements. | Readers run in parallel: 3.6× faster than `.lock` at 1k elements and 8.9× at 10k, still 2× with half the operations writes. It breaks even around 256 elements and is 1.5–30× slower for short operations. |
| Actor types | The caller is already `async`, and you'd rather suspend than block a thread. | No thread blocks while waiting. Each call still pays an actor hop, and short single-index operations are slower than `.lock` (`count` ~25 ns vs. `.lock`'s ~4.5 ns; a contended 8-way read ~262 ns vs. ~44 ns). Closure-based scans, though, are no longer the outlier they once were: the actor types are `final` with every public member `@inlinable`, so a call through a captured instance (the common case for a `Task`/`TaskGroup` closure) is devirtualized and specialized instead of going through a generic vtable call. A contended `count(where:)` scan over 10k elements went from ~421,959 ns to ~4,108 ns — now faster than `.lock`'s ~8,505 ns at that size, though still a few times slower than `.readerWriterLock`'s ~1,047 ns. |

Measured on one machine; see [Benchmarks](#benchmarks) for every row.

### Why not `DispatchQueue`?

A concurrent `DispatchQueue` with barrier writes is the classic reader-writer pattern, and `ThreadSafe` used it originally. It was removed because it can't support the subscript semantics this library promises:

- **Atomic in-place edits need a lock that can be held across a `yield`.** `ts[i] += 1` and `dict[k]?.append(x)` run through a `_modify` accessor, which holds exclusive access while the caller's code edits the value in place. GCD only provides exclusivity *inside* a `queue.sync { }` closure, and you can't `yield` out of a closure. With a queue, those edits split into a separate read and write, which loses updates under concurrency.
- **The only queue-based workaround is fragile.** "Parking" the queue (an async barrier block that waits on a semaphore until the edit finishes) ties up a GCD worker thread for each compound edit, and can stall the main thread behind a low-priority worker, since semaphores don't boost priority.
- **Reentrancy could deadlock silently.** A read nested inside another read (e.g. `ts.count` inside `ts.forEach { }`) hung forever as soon as a writer queued between them, instead of trapping.

`.lock` and `.readerWriterLock` lock and unlock manually, so a subscript's in-place edit holds the lock for exactly the access, and same-instance reentry traps immediately. See [Benchmarks](#benchmarks) for current per-operation costs.

`Value`'s shape determines which members are available, added via constrained extensions:

| `Value` shape | Members |
|---|---|
| Any `Sendable` | `wrappedValue`, `projectedValue`, `mutate(_:)`, plus unconditional `description` |
| `Collection` | `count`, `isEmpty`, `forEach`, `map`, `reduce(into:)`, `reduce(_:_:)`, `first(where:)`, `contains(where:)`, `count(where:)`, `min(by:)`, `max(by:)`, `randomElement()`, `allSatisfy(_:)`, `compactMap(_:)`, `sorted(by:)`, `subscript(safe:)`* |
| `Collection`, `Element: Comparable` | + `sorted()`, `min()`, `max()` |
| `BidirectionalCollection` | + `first`, `last` |
| `RangeReplaceableCollection` | + `elements`, `append`, `append(contentsOf:)`, `removeAll`, `removeAll(where:)`, `removeFirst()`/`removeFirst(_:)`, `reserveCapacity(_:)`, `filter(_:)`, `prefix(_:)`/`suffix(_:)` (returning `[Element]`), init with no initial value, init from any `Sequence` |
| `RangeReplaceableCollection`, `Element: Equatable` | + `contains(_:)` |
| `RangeReplaceableCollection`* | + `remove(at:)`, `insert(_:at:)`, `insert(contentsOf:at:)`, `removeSubrange(_:)`, `replaceSubrange(_:with:)`, `firstIndex(where:)` |
| `RangeReplaceableCollection`*, `Element: Equatable` | + `firstIndex(of:)` |
| `RangeReplaceableCollection & BidirectionalCollection` (e.g. `Array`) | + `popLast()`, `removeLast()`/`removeLast(_:)` |
| `MutableCollection`* | + `subscript(index:)` (get + atomic in-place modify), `swapAt(_:_:)` |
| `MutableCollection & BidirectionalCollection` | + `reverse()` |
| `MutableCollection & RandomAccessCollection` | + `sort(by:)`, `shuffle()` |
| `MutableCollection & RandomAccessCollection`, `Element: Comparable` | + `sort()` |
| Dictionary-shaped (`Key`/`Value` keyed storage) | `dictionary`, `keys`, `values`, `removeValue(forKey:)`, `updateValue(_:forKey:)`, `removeAll`, `merge(_:uniquingKeysWith:)` (whole-dictionary), `subscript(key:)` (get + atomic in-place modify), init with no initial value |
| `Dictionary<Key, Value>` (concrete) | + `mapValues(_:)`, `compactMapValues(_:)`, `filter(_:)` (`-> [Key: Value]`), `reserveCapacity(_:)`, `popFirst()`, `merge(_:uniquingKeysWith:)` (sequence-of-pairs), `subscript(key:default:)` (get + atomic in-place modify) |
| `SetAlgebra` (e.g. `Set`) | `elements`, `contains(_:)`, `insert(_:)`, `remove(_:)`, `update(with:)`, `removeAll()`, `union(_:)`, `intersection(_:)`, `symmetricDifference(_:)`, `subtracting(_:)`, `formUnion(_:)`, `formIntersection(_:)`, `subtract(_:)`, `formSymmetricDifference(_:)`, `isSubset(of:)`, `isSuperset(of:)`, `isDisjoint(with:)`, `isStrictSubset(of:)`, `isStrictSuperset(of:)`, init with no initial value |
| `Set<Element>` (concrete) | + `popFirst()`, `removeFirst()`, `filter(_:)` (`-> Set<Element>`), `reserveCapacity(_:)`, `removeAll(keepingCapacity:)` |

\* Also requires `Value.Index: Sendable` — satisfied by `Array`, `Dictionary`, `Set`, and `String`, but not guaranteed for every `Collection`.

`ThreadSafe<[Element]>` picks up the `Collection` + `RangeReplaceableCollection` + `BidirectionalCollection` + `MutableCollection` rows, so it gets the array API. `ThreadSafe<[Key: Value]>` picks up `Collection` (giving free `count`/`isEmpty`/`forEach`/`map`/`reduce`/`first(where:)`/`contains(where:)`/etc., but not `first`/`last` — `Dictionary` isn't a `BidirectionalCollection`, and its iteration order isn't meaningful) plus the dictionary-shaped rows. `ThreadSafe<Set<Element>>` picks up `Collection` (same caveat — no `first`/`last`) plus the `SetAlgebra` and `Set<Element>` rows. Any other `Sendable` shape gains whichever rows it structurally satisfies for free — `ThreadSafe<String>` gets `Collection` members for free (e.g. `ThreadSafe("hello").count == 5`).

Members use the standard library's own names and signatures, so using `ThreadSafe<[Element]>`/`ThreadSafe<Set<Element>>` feels like using `Array`/`Set` directly. Members that don't fit a lock-wrapped value are left out: lazy views, iterators, unsafe buffer access, and index-returning lookups like `lastIndex(of:)`. `contains(_:)` (Array shape) is scoped to `RangeReplaceableCollection`, not the general `Collection` row, since `Set` already has its own `SetAlgebra`-based `contains(_:)`. Members the stdlib declares only on the concrete `Dictionary`/`Set` type (not on the protocols behind the generic rows) are in the concrete rows. For anything genuinely missing, drop into `mutate(_:)`/`read`-style access on `elements`/`dictionary`/`wrappedValue` directly.

Alongside `ThreadSafe<Value>`, four real actors cover the async case — `ThreadSafeArray<Element>`, `ThreadSafeDictionary<Key, Value>`, `ThreadSafeSet<Element>`, and `ThreadSafeAtomic<Value>`:

| Kind | `ThreadSafe` (sync) | Actor (async) |
|---|---|---|
| Single value | `ThreadSafe<Value>` (property wrapper) | `ThreadSafeAtomic<Value>` |
| Array | `ThreadSafe<[Element]>` (also usable as a property wrapper) | `ThreadSafeArray<Element>` |
| Dictionary | `ThreadSafe<[Key: Value]>` (also usable as a property wrapper) | `ThreadSafeDictionary<Key, Value>` |
| Set | `ThreadSafe<Set<Element>>` (also usable as a property wrapper) | `ThreadSafeSet<Element>` |

**Actor types** — `ThreadSafeArray`, `ThreadSafeDictionary`, `ThreadSafeSet`, `ThreadSafeAtomic`: real actors, isolated by Swift's runtime. Access needs `await`, and callers suspend instead of blocking a thread. Safe under strict concurrency by construction. See [Which to use](#which-to-use). There is no naming overlap — the sync type is always spelled `ThreadSafe<...>`, and the array/dictionary/set/atomic names belong exclusively to the actors.

When `Value` is `Equatable`, so is `ThreadSafe<Value>`. Actor types aren't — `==` is synchronous but reading actor-isolated state needs `await`, so compare the plain value at the call site instead. For encoding and decoding, see [Codable](#codable).

`ThreadSafe<Value>` is deliberately **not** `Hashable`, even when `Value` is: hashing/equality-for-Set-membership requires a member's hash to never change while it's a member (`Set` never re-buckets an existing element), which a reference type with mutable contents can't promise — mutating a `ThreadSafe` after inserting it into a `Set` or using it as a `Dictionary` key corrupts the table. Deduplicate/hash by content instead: `Set(instances.map(\.wrappedValue))`.

`ThreadSafe<Value>` conforms to `CustomStringConvertible` unconditionally — `description` prints `ThreadSafe(<contents>)` (e.g. `ThreadSafe(42)`, `ThreadSafe([1, 2, 3])`), the same generic form regardless of shape. Actor types don't get this either, for the same synchronous-access reason.

All mutation goes through `mutate(_:)` (or dedicated methods like `append`/`updateValue`) — direct assignment to `wrappedValue` is unavailable, since read-modify-write isn't atomic across two separate lock acquisitions.

`wrappedValue`/`elements`/`dictionary` (and the actor equivalents) are snapshot reads, safe for value-type `Value`s (`Array`/`Dictionary`/`Set`/`String`/scalars) — mutating the returned snapshot only mutates your local copy, not the shared instance. If `Value` is a reference type instead, the accessor hands back the same instance, not a copy, so mutating through it bypasses the lock/actor entirely and races with any other access. `ThreadSafe`/the actors only make value-type payloads safe this way; wrapping a reference type still requires not mutating it outside `mutate(_:)`.

## Benchmarks

Per-operation cost of each type and mechanism against the raw stdlib type. The table below is regenerated by the benchmark tool (see [Testing](#testing)); [Benchmarks/RESULTS.md](Benchmarks/RESULTS.md) has the full legend, run-to-run comparison, and system details.

<!-- BENCHMARKS:START -->
<!-- Generated by ThreadSafeKitBenchmarks (--readme); edits between these markers are overwritten. -->

| Operation                                |  Raw |   actor |    .lock | .readerWriterLock | Spread |
| ---------------------------------------- | ---: | ------: | -------: | ----------------: | -----: |
| Array count                              |  5.7 |    24.9 |      4.5 |              20.1 |    ±6% |
| Array a[i] get                           |  5.8 |    24.4 |      4.5 |              20.5 |    ±4% |
| Array a[i] = v                           |  2.0 |    29.1 |     30.1 |              46.0 |    ±3% |
| Array a[i] += 1                          |  2.0 |    29.3 |     11.6 |              27.5 |    ±4% |
| Array append + popLast                   |  2.5 |    31.4 |     19.8 |              50.7 |    ±3% |
| Array elements snapshot                  |  5.9 |    27.7 |      8.0 |              23.5 |    ±4% |
| Array contains(where:)                   | 22.9 |    41.5 |     23.5 |              40.1 |    ±4% |
| Dictionary d[k] get                      |  9.5 |    32.8 |      8.5 |              24.7 |    ±4% |
| Dictionary d[k] = v                      |  6.8 |    34.3 |     18.5 |              34.0 |    ±3% |
| Dictionary d[k]! += 1                    |  6.1 |    32.5 |     16.7 |              32.6 |    ±2% |
| Dictionary d[k, default: 0] += 1         |  9.2 |    32.7 |     17.0 |              32.5 |    ±2% |
| Dictionary updateValue                   |  7.3 |    33.1 |     13.7 |              29.2 |    ±4% |
| Set contains                             |  8.7 |    27.4 |      7.2 |              23.2 |    ±3% |
| Set insert + remove                      | 12.6 |    67.6 |     25.7 |              55.7 |    ±2% |
| Scalar read                              |  1.8 |    24.3 |      4.3 |              20.2 |    ±4% |
| Scalar mutate { += 1 }                   |  1.3 |    24.0 |      3.8 |              19.7 |    ±8% |
| Contended 90% read / 10% write           |    - |   236.0 |     48.7 |           1,425.6 |    ±8% |
| Contended 100% read                      |    - |   261.8 |     43.7 |             325.8 |   ±12% |
| Contended 100% write (a[i] += 1)         |    - |    16.9 |     80.0 |           2,295.6 |    ±3% |
| Contended long read (count(where:), 64)  |    - |   283.3 |    150.5 |             385.6 |    ±3% |
| Contended long read (count(where:), 256) |    - |   373.8 |    452.6 |             366.5 |   ±11% |
| Contended long read (count(where:), 1k)  |    - |   654.8 |  1,098.1 |             309.7 |    ±7% |
| Contended long read (count(where:), 10k) |    - | 4,108.3 |  8,504.8 |           1,046.6 |    ±4% |
| Contended long read + 10% write          |    - | 3,627.5 | 12,353.6 |           2,997.9 |   ±10% |
| Contended long read + 50% write          |    - | 2,127.8 |  6,879.3 |           3,436.8 |    ±9% |

Nanoseconds per operation (ns/op), lower is better; median of 5 runs. **Raw** is the unsynchronized stdlib type on one thread; **actor** is the actor type (`ThreadSafeArray`/…); **.lock** / **.readerWriterLock** are `ThreadSafe<Value>` with that mechanism; **Spread** is run-to-run variation. Contended rows are 8 concurrent workers on one instance (no Raw figure: that would be a data race). Measured on Apple M4 Max (Mac16,6), macOS Version 26.6.2 (Build 25G83), 2026-09-25T01:56:19Z. Numbers are only comparable on the same machine. Full legend and baseline comparison: [Benchmarks/RESULTS.md](Benchmarks/RESULTS.md).
<!-- BENCHMARKS:END -->

## Testing

```
swift test
```

Also run with the Thread Sanitizer before trusting a change to locking/concurrency behavior — plain `swift test` won't catch a data race:

```
swift test --sanitize=thread
```

Run TSan on the default debug build. In a release build (`-c release -Xswiftc -enable-testing --sanitize=thread`), it can intermittently report a data race in `concurrentReadSnapshotsAreInternallyConsistent`. That's a false positive: once the `@inlinable` members are specialized, the array's copy-on-write buffer write happens in instrumented code, but TSan can't see the Swift runtime's reference counting that orders it after the reader drops its copy. A plain `Array` behind a plain `pthread_rwlock` reports the same thing. The timing-based tests also fail under TSan, since it slows everything down.

Timing-based tests (fixed absolute-time or relative-overhead ceilings) are tagged `.performance` and flaky under CI/parallel load; `swift test --filter`/`--skip` only support regexes, not tags, on this toolchain, so name-based regexes select them instead:

```
swift test --skip 'Fast|Bounded|CostDoesNotScaleWithCollectionSize'   # correctness only
swift test --filter 'Fast|Bounded|CostDoesNotScaleWithCollectionSize' # performance only
```

New performance tests must be tagged `.performance` **and** named to end in `Fast`, `Bounded`, or `CostDoesNotScaleWithCollectionSize`, or these commands will misclassify them.

The performance tests are regression guards, not measurements — `swift test` builds debug and runs tests in parallel. For real per-operation numbers, run the release-mode benchmark. It prints a table of ns/op for each operation on the raw stdlib type, the actor type, and `ThreadSafe` under `.lock` and `.readerWriterLock` (single-thread and 8-way contended). Each figure is the median of several whole-suite runs, and each run is compared against the committed baseline ([Benchmarks/RESULTS.md](Benchmarks/RESULTS.md), with its raw numbers in `Benchmarks/RESULTS.json`). A change is flagged only if it's larger than the threshold and the runs' own noise, and only when the baseline came from the same machine. The legend under the table explains every column.

```
swift run -c release ThreadSafeKitBenchmarks                                    # compare against the baseline
swift run -c release ThreadSafeKitBenchmarks --output Benchmarks/RESULTS.md --readme README.md   # also write RESULTS.md + RESULTS.json (new baseline) and the README table
swift run -c release ThreadSafeKitBenchmarks --strict                           # exit 1 if anything is flagged slower
```

Other options: `--runs <n>` (default 5), `--threshold <percent>` (default 30), `--baseline <path>`. When a change affects performance, run the benchmark, investigate anything flagged ⚠️ SLOWER, then regenerate with `--output … --readme README.md` and commit `Benchmarks/` and the README with the change.

## Contributing

Mark every new public `ThreadSafe` member `@inlinable`, and make anything it touches `@usableFromInline` rather than `private`. Without that, apps call it through unspecialized generic code, which adds roughly 40–200 ns per call on top of the lock (see [Benchmarks](#benchmarks)). `SourceConventionTests` fails if a public member is missing `@inlinable`.

The same rule applies to the actor types (`ThreadSafeArray`, `ThreadSafeDictionary`, `ThreadSafeSet`, `ThreadSafeAtomic`): mark every new public member `@inlinable`, and keep their storage `@usableFromInline` rather than `private`. Actors need one more thing `ThreadSafe` doesn't: they're declared `public final actor`, and must stay `final`. Swift doesn't treat actors as implicitly `final`, so a call through a captured instance — e.g. inside a `@Sendable` closure passed to a `Task`, which is how most real callers and the contended benchmarks use them — compiles to a vtable call that can't be devirtualized or inlined even when the callee is `@inlinable`. `SourceConventionTests` fails if one isn't; removing `final` would reintroduce that vtable call and the unspecialized-generic-code cost it carries. Members shared by all four actors (`mutate` plus the read-only `Collection` members) live once in `_ThreadSafeActorStorage`'s protocol extension (`Sources/ThreadSafeKit/ThreadSafeActorStorage.swift`) instead of being copy-pasted per actor — add a new shared member there, and keep only shape-specific members on the actor itself.
