# ThreadSafeKit

Thread-safe wrapper types for Swift 6+ strict concurrency. Each type is `Sendable`, so mutable state passes across isolation domains without data races, no manual locking at call site.

## Requirements

- Swift 6.3+ tools, `swiftLanguageModes: [.v6]`
- iOS 17+, tvOS 17+, macOS 14+

## Install

```swift
.package(url: "<repo-url>", from: "1.0.0")
```

## Usage

```swift
@ThreadSafe var counter = 0
_counter.mutate { $0 += 1 }

@ThreadSafe var items = [1, 2, 3]
$items.append(4)   // items == [1, 2, 3, 4]

@ThreadSafe(mechanism: .lock) var cache = ["key": 1]
$cache["other"] = 2   // cache == ["key": 1, "other": 2]

let list = ThreadSafeArray<Int>()
await list.append(1)
let all = await list.elements
```

`ThreadSafe<Value>` also works as a plain instance (`let list = ThreadSafe<[Int]>()`) when you don't want property-wrapper sugar.

A property wrapper's backing storage is always a `var` (`@ThreadSafe var items` generates a stored `var _items`), and a `Sendable` class can't have any mutable stored property — so `@ThreadSafe` can't be used in a `Sendable` class. Use the plain instance as a `let` instead. `Sendable` structs are fine: a struct may hold a `var` of `Sendable` type (and copies of the struct share the same underlying `ThreadSafe` instance).

```swift
final class Store: Sendable {
    @ThreadSafe var items: [Int] = []   // ❌ error: stored property '_items' of
                                         //    'Sendable'-conforming class 'Store' is mutable
}

final class Store: Sendable {
    let items = ThreadSafe<[Int]>()      // ✅ use the type directly, as a `let`
}

struct Settings: Sendable {
    @ThreadSafe var count = 0            // ✅ fine in a struct
}
```

Don't reach for `@unchecked Sendable` to silence the class error — the `let` form above is already correctly `Sendable`.

### Subscripts are atomic

`ts[i] += 1`, `dict[k]! += 1`, `dict[k]?.append(x)`, and plain `ts[i] = v`/`dict[k] = v` are each a single atomic access — the write lock is held across the entire get-modify-set, so concurrent compound assignment through a subscript can't lose updates. `ts[i] = ts[i] + 1`, however, is *two* separate accesses (a `get`, then a full `set`), so it is **not** atomic — the two accesses can interleave with another caller's write in between. Use `+=` (or `mutate`, below) for anything that needs to be a single step.

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

`mutate(_:)` holds the lock/queue/actor across the whole closure, so a multi-step read-then-write is atomic as one unit:

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

**What this does and doesn't fix.** Every type here is already fully thread-safe — no data races, no memory corruption, no crashes, on any single call, with or without `mutate`. The bug `mutate` fixes is a different, narrower one: a *logical* race (check-then-act / TOCTOU) that shows up when a correct outcome depends on two or more calls happening as one step. That race is a bug in your call sequence, not in the underlying storage — but you need `mutate` to close it, since there's no other way to hold the lock/queue/actor across multiple steps. `mutate` doesn't add thread safety that was missing; it adds the ability to make a multi-step operation indivisible.

### Codable and Equatable

`ThreadSafe<Value>` conforms conditionally — only when `Value` does — regardless of `mechanism`:

```swift
let counter = ThreadSafe(wrappedValue: 42)
let data = try JSONEncoder().encode(counter)
let decoded = try JSONDecoder().decode(ThreadSafe<Int>.self, from: data)

let cache = ThreadSafe(["a": 1])
cache == ThreadSafe(["a": 1])   // true

struct Container: Codable, Equatable {
    let items: ThreadSafe<[Int]>   // synthesis works because ThreadSafe<[Int]> is itself Codable/Equatable
}
```

Not `Hashable` — see above: a member's hash must never change while it's in a `Set`/used as a
`Dictionary` key, which a mutable reference type can't promise. `Container` above can't add
`Hashable` to its own conformance list either, for the same reason (its `items` field is still a
mutable reference under the hood, `let` only stops reassignment, not mutation through it).

Actor types (`ThreadSafeArray`, `ThreadSafeDictionary`, `ThreadSafeSet`, `ThreadSafeAtomic`) don't conform to either — `Encodable.encode(to:)` and `==` are synchronous, but reading actor-isolated state needs `await`. Snapshot manually instead:

```swift
let snapshot = await list.elements
let data = try JSONEncoder().encode(snapshot)
// ...
let restored = ThreadSafeArray(try JSONDecoder().decode([Int].self, from: data))

await list.elements == (await otherList.elements)   // compare the plain snapshots
```

This also rules out `@MainActor`-style isolated conformances: that mechanism ties a conformance to one specific *global* actor, checked statically. `ThreadSafeArray<Element>`/`ThreadSafeDictionary<Key, Value>`/`ThreadSafeSet<Element>`/`ThreadSafeAtomic<Value>` are plain `actor` types — each instance is its own isolation domain, so there's no single actor to name, and it wouldn't remove the `await` for a caller outside the isolated instance anyway.

## Types

Shape-specific members mirror the standard library's own `Array`/`Dictionary`/`Set` names, so the API can be guessed from stdlib familiarity; the wrapper-only members are `mutate`, `wrappedValue`/`$name`, the snapshot accessors (`elements`/`dictionary`), and `subscript(safe:)`.

One generic type, `ThreadSafe<Value>`, backs the sync API. Pick the backing mechanism via `ThreadSafeMechanism` (default `.readerWriterLock`): `.readerWriterLock` (`pthread_rwlock_t`, locked manually — concurrent reads, exclusive writes) or `.lock` (`OSAllocatedUnfairLock`, every access fully exclusive — reads included). `ThreadSafe<Value>` itself is `@unchecked Sendable` regardless of which mechanism you pick — the choice is a runtime backing detail, not a type-level distinction, and safety is enforced internally (locking) rather than by the compiler either way.

Subscripts (`ts[i]`, `dict[k]`) are atomic for the whole access under either mechanism, including compound forms like `ts[i] += 1` and `dict[k]?.append(x)` — see "Subscripts are atomic" below.

`Value`'s shape determines which members are available, added via constrained extensions:

| `Value` shape | Members |
|---|---|
| Any `Sendable` | `wrappedValue`, `projectedValue`, `mutate(_:)`, plus unconditional `description` |
| `Collection` | `count`, `isEmpty`, `forEach`, `map`, `reduce(into:)`, `subscript(safe:)`* |
| `BidirectionalCollection` | + `first`, `last` |
| `RangeReplaceableCollection` | + `elements`, `append`, `append(contentsOf:)`, `removeAll`, `removeAll(where:)`, `removeFirst()`/`removeFirst(_:)`, `reserveCapacity(_:)`, `filter(_:)`, `compactMap(_:)`, `sorted(by:)`, `allSatisfy(_:)`, `prefix(_:)`/`suffix(_:)` (returning `[Element]`), init with no initial value, init from any `Sequence` |
| `RangeReplaceableCollection`, `Element: Equatable` | + `contains(_:)` |
| `RangeReplaceableCollection`, `Element: Comparable` | + `sorted()`, `min()`, `max()` |
| `RangeReplaceableCollection`* | + `remove(at:)`, `insert(_:at:)`, `insert(contentsOf:at:)`, `removeSubrange(_:)`, `replaceSubrange(_:with:)`, `firstIndex(where:)` |
| `RangeReplaceableCollection`*, `Element: Equatable` | + `firstIndex(of:)` |
| `RangeReplaceableCollection & BidirectionalCollection` (e.g. `Array`) | + `popLast()`, `removeLast()`/`removeLast(_:)` |
| `MutableCollection`* | + `subscript(index:)` (get + atomic in-place modify) |
| `MutableCollection & BidirectionalCollection` | + `reverse()` |
| `MutableCollection & RandomAccessCollection` | + `sort(by:)`, `shuffle()` |
| `MutableCollection & RandomAccessCollection`, `Element: Comparable` | + `sort()` |
| Dictionary-shaped (`Key`/`Value` keyed storage) | `dictionary`, `keys`, `values`, `removeValue(forKey:)`, `updateValue(_:forKey:)`, `removeAll`, `merge`, `subscript(key:)` (get + atomic in-place modify), init with no initial value |
| `Dictionary<Key, Value>` (concrete) | + `mapValues(_:)`, `compactMapValues(_:)`, `filter(_:)` (`-> [Key: Value]`), `contains(where:)` |
| `SetAlgebra` (e.g. `Set`) | `elements`, `contains(_:)`, `insert(_:)`, `remove(_:)`, `update(with:)`, `removeAll`, `union(_:)`, `intersection(_:)`, `symmetricDifference(_:)`, `formUnion(_:)`, `formIntersection(_:)`, `subtract(_:)`, `formSymmetricDifference(_:)`, `isSubset(of:)`, `isSuperset(of:)`, `isDisjoint(with:)`, `isStrictSubset(of:)`, `isStrictSuperset(of:)`, init with no initial value |

\* Also requires `Value.Index: Sendable` — satisfied by `Array`, `Dictionary`, `Set`, and `String`, but not guaranteed for every `Collection`.

`ThreadSafe<[Element]>` picks up the `Collection` + `RangeReplaceableCollection` + `BidirectionalCollection` + `MutableCollection` rows, so it gets the full array API. `ThreadSafe<[Key: Value]>` picks up `Collection` (giving free `count`/`isEmpty`/`forEach`/`map`/`reduce`/`subscript(safe:)`, but not `first`/`last` — `Dictionary` isn't a `BidirectionalCollection`, and its iteration order isn't meaningful) plus the dictionary-shaped rows. `ThreadSafe<Set<Element>>` picks up `Collection` (same caveat — no `first`/`last`) plus the `SetAlgebra` row. Any other `Sendable` shape gains whichever rows it structurally satisfies for free — `ThreadSafe<String>` gets `Collection` members for free (e.g. `ThreadSafe("hello").count == 5`).

`RangeReplaceableCollection` and `SetAlgebra` cover their full stdlib surface for `Array`/`Set`-shaped values — 1:1 mirrors of the underlying type's own API, so using `ThreadSafe<[Element]>`/`ThreadSafe<Set<Element>>` feels like using `Array`/`Set` directly. `contains(_:)` (Array shape) is scoped to `RangeReplaceableCollection`, not the general `Collection` row, since `Set` already has its own `SetAlgebra`-based `contains(_:)`. For anything genuinely missing, drop into `mutate(_:)`/`read`-style access on `elements`/`dictionary`/`wrappedValue` directly.

Alongside `ThreadSafe<Value>`, four real actors cover the async case — `ThreadSafeArray<Element>`, `ThreadSafeDictionary<Key, Value>`, `ThreadSafeSet<Element>`, and `ThreadSafeAtomic<Value>`:

| Kind | `ThreadSafe` (sync) | Actor (async) |
|---|---|---|
| Single value | `ThreadSafe<Value>` (property wrapper) | `ThreadSafeAtomic<Value>` |
| Array | `ThreadSafe<[Element]>` (also usable as a property wrapper) | `ThreadSafeArray<Element>` |
| Dictionary | `ThreadSafe<[Key: Value]>` (also usable as a property wrapper) | `ThreadSafeDictionary<Key, Value>` |
| Set | `ThreadSafe<Set<Element>>` (also usable as a property wrapper) | `ThreadSafeSet<Element>` |

**Actor types** — `ThreadSafeArray`, `ThreadSafeDictionary`, `ThreadSafeSet`, `ThreadSafeAtomic`: real actors, isolated by Swift's runtime. Access needs `await`. No lock contention, safe under strict concurrency by construction. Pick actor types when the caller is already async; pick `ThreadSafe<Value>` when it isn't. There is no naming overlap — the sync type is always spelled `ThreadSafe<...>`, and the array/dictionary/set/atomic names belong exclusively to the actors.

When the wrapped value is `Codable`, so is `ThreadSafe<Value>`, regardless of mechanism (though decoding always produces a default-mechanism (`.readerWriterLock`) instance — the mechanism itself isn't part of the encoded representation, so a `.lock`-backed instance won't round-trip back to `.lock`). Same for `Equatable`. Actor types are intentionally neither — both require synchronous access (`Encodable.encode(to:)`, `==`) but reading actor-isolated state needs `await`; snapshot via `elements`/`dictionary`/`get()`/direct `await` and restore via `init(_:)`, or compare the plain value at the call site instead.

`ThreadSafe<Value>` is deliberately **not** `Hashable`, even when `Value` is: hashing/equality-for-Set-membership requires a member's hash to never change while it's a member (`Set` never re-buckets an existing element), which a reference type with mutable contents can't promise — mutating a `ThreadSafe` after inserting it into a `Set` or using it as a `Dictionary` key corrupts the table. Deduplicate/hash by content instead: `Set(instances.map(\.wrappedValue))`.

`ThreadSafe<Value>` conforms to `CustomStringConvertible` unconditionally — `description` prints `ThreadSafe(<contents>)` (e.g. `ThreadSafe(42)`, `ThreadSafe([1, 2, 3])`), the same generic form regardless of shape. Actor types don't get this either, for the same synchronous-access reason.

All mutation goes through `mutate(_:)` (or dedicated methods like `append`/`updateValue`) — direct assignment to `wrappedValue`/`value` is unavailable, since read-modify-write isn't atomic across two separate lock acquisitions.

`wrappedValue`/`elements`/`dictionary` (and the actor equivalents) are snapshot reads, safe for value-type `Value`s (`Array`/`Dictionary`/`Set`/`String`/scalars) — mutating the returned snapshot only mutates your local copy, not the shared instance. If `Value` is a reference type instead, the accessor hands back the same instance, not a copy, so mutating through it bypasses the lock/queue/actor entirely and races with any other access. `ThreadSafe`/the actors only make value-type payloads safe this way; wrapping a reference type still requires not mutating it outside `mutate(_:)`.

## Testing

```
swift test
```

Also run with the Thread Sanitizer before trusting a change to locking/concurrency behavior — plain `swift test` won't catch a data race, and this package has had real races only TSan caught in the past:

```
swift test --sanitize=thread
```

Timing-based tests (fixed absolute-time or relative-overhead ceilings) are tagged `.performance` and flaky under CI/parallel load; `swift test --filter`/`--skip` only support regexes, not tags, on this toolchain, so name-based regexes select them instead:

```
swift test --skip 'Fast|Bounded|CostDoesNotScaleWithCollectionSize'   # correctness only
swift test --filter 'Fast|Bounded|CostDoesNotScaleWithCollectionSize' # performance only
```

New performance tests must be tagged `.performance` **and** named to end in `Fast`, `Bounded`, or `CostDoesNotScaleWithCollectionSize`, or these commands will misclassify them.
