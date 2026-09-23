# ThreadSafeKit

Thread-safe wrapper types for Swift 6+ strict concurrency. Each type is `Sendable`, so mutable state passes across isolation domains without data races, no manual locking at call site.

## Requirements

- Swift 6.3+ tools, `swiftLanguageModes: [.v6]`
- iOS 17+, tvOS 17+, macOS 14+

## Install

```swift
.package(url: "<repo-url>", from: "1.0.0")
```

## Types

One generic type, `ThreadSafe<Value>`, backs the sync API. Pick the backing mechanism via `ThreadSafeMechanism` (default `.dispatchQueue`): `.lock` (`OSAllocatedUnfairLock`, real/checked `Sendable`, low-contention short critical sections) or `.dispatchQueue` (concurrent queue + barrier writes — reads run in parallel, writes are exclusive; `@unchecked Sendable`, safety enforced internally, not by the compiler).

`Value`'s shape determines which members are available, added via constrained extensions:

| `Value` shape | Members |
|---|---|
| Any `Sendable` | `wrappedValue`, `mutate(_:)` |
| `Collection` | `count`, `isEmpty`, `forEach`, `map`, `reduce(into:)`, `subscript(safe:)` |
| `BidirectionalCollection` | + `first`, `last` |
| `RangeReplaceableCollection` | + `append`, `push`, `removeAll`, `remove(at:)`, init with no initial value, init from any `Sequence` |
| `RangeReplaceableCollection & BidirectionalCollection` (e.g. `Array`) | + `pop()` |
| `MutableCollection` | + `subscript(index:)` (get/set) |
| Dictionary-shaped (`Key`/`Value` keyed storage) | `dictionary`, `getValue(forKey:)`, `setValue(_:forKey:)`, `removeValue(forKey:)`, `removeAll`, `merge`, `subscript(key:)`, init with no initial value |

`ThreadSafe<[Element]>` picks up the `Collection` + `RangeReplaceableCollection` + `BidirectionalCollection` + `MutableCollection` rows, so it gets the full array API. `ThreadSafe<[Key: Value]>` picks up `Collection` (giving free `count`/`isEmpty`/`forEach`/`reduce`, but not `first`/`last` — `Dictionary` isn't a `BidirectionalCollection`, and its iteration order isn't meaningful) plus the dictionary-shaped row. Any other `Sendable` shape gains whichever rows it structurally satisfies for free — `ThreadSafe<String>` and `ThreadSafe<Set<Int>>` both get `Collection` members (e.g. `ThreadSafe("hello").count == 5`).

Alongside `ThreadSafe<Value>`, three real actors cover the async case — `ThreadSafeArray<Element>`, `ThreadSafeDictionary<Key, Value>`, and `ThreadSafeAtomic<Value>`:

| Kind | `ThreadSafe` (sync) | Actor (async) |
|---|---|---|
| Single value | `ThreadSafe<Value>` (property wrapper) | `ThreadSafeAtomic<Value>` |
| Array | `ThreadSafe<[Element]>` (also usable as a property wrapper) | `ThreadSafeArray<Element>` |
| Dictionary | `ThreadSafe<[Key: Value]>` (also usable as a property wrapper) | `ThreadSafeDictionary<Key, Value>` |

**Actor types** — `ThreadSafeArray`, `ThreadSafeDictionary`, `ThreadSafeAtomic`: real actors, isolated by Swift's runtime. Access needs `await`. No lock contention, safe under strict concurrency by construction. Pick actor types when the caller is already async; pick `ThreadSafe<Value>` when it isn't. There is no naming overlap — the sync type is always spelled `ThreadSafe<...>`, and the array/dictionary/atomic names belong exclusively to the actors.

When the wrapped value is `Codable`, so is `ThreadSafe<Value>`, regardless of mechanism. Same for `Equatable` and `Hashable`. Actor types are intentionally none of these — all three require synchronous access (`Encodable.encode(to:)`, `==`, `hash(into:)`) but reading actor-isolated state needs `await`; snapshot via `elements`/`dictionary`/direct `await` and restore via `init(_:)`, or compare/hash the plain value at the call site instead.

`ThreadSafe<Value>` conforms to `CustomStringConvertible` unconditionally — `description` prints `ThreadSafe(<contents>)` (e.g. `ThreadSafe(42)`, `ThreadSafe([1, 2, 3])`), the same generic form regardless of shape. Actor types don't get this either, for the same synchronous-access reason.

All mutation goes through `mutate(_:)` (or dedicated methods like `append`/`setValue`) — direct assignment to `wrappedValue`/`value` is unavailable, since read-modify-write isn't atomic across two separate lock acquisitions.

## Usage

```swift
@ThreadSafe var counter = 0
_counter.mutate { $0 += 1 }

@ThreadSafe var items = [1, 2, 3]
$items.append(4)   // items == [1, 2, 3, 4]

@ThreadSafe(mechanism: .lock) var cache = ["key": 1]
$cache.setValue(2, forKey: "other")   // cache == ["key": 1, "other": 2]

let list = ThreadSafeArray<Int>()
await list.append(1)
let all = await list.elements
```

`ThreadSafe<Value>` also works as a plain instance (`let list = ThreadSafe<[Int]>()`) when you don't want property-wrapper sugar.

### Compound operations with `mutate`

Every individual call (`append`, `setValue`, subscripts, …) is atomic on its own, but two separate calls are not atomic *together* — a read followed by a write can race with another caller's write in between:

```swift
// NOT safe: another writer can slip in between these two calls
if await dict.getValue(forKey: "x") == nil {
    await dict.setValue(1, forKey: "x")
}
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

counter.mutate { $0 += 1 }   // ThreadSafe already works this way, regardless of mechanism
```

**What this does and doesn't fix.** Every type here is already fully thread-safe — no data races, no memory corruption, no crashes, on any single call, with or without `mutate`. The bug `mutate` fixes is a different, narrower one: a *logical* race (check-then-act / TOCTOU) that shows up when a correct outcome depends on two or more calls happening as one step. That race is a bug in your call sequence, not in the underlying storage — but you need `mutate` to close it, since there's no other way to hold the lock/queue/actor across multiple steps. `mutate` doesn't add thread safety that was missing; it adds the ability to make a multi-step operation indivisible.

### Codable, Equatable, and Hashable

`ThreadSafe<Value>` conforms conditionally — only when `Value` does — regardless of `mechanism`:

```swift
let counter = ThreadSafe(wrappedValue: 42)
let data = try JSONEncoder().encode(counter)
let decoded = try JSONDecoder().decode(ThreadSafe<Int>.self, from: data)

let cache = ThreadSafe(["a": 1])
cache == ThreadSafe(["a": 1])   // true

let seen: Set<ThreadSafe<[Int]>> = [ThreadSafe([1, 2]), ThreadSafe([1, 2])]   // one element

struct Container: Codable, Equatable, Hashable {
    let items: ThreadSafe<[Int]>   // synthesis works because ThreadSafe<[Int]> is itself Codable/Equatable/Hashable
}
```

`Hashable` forwards straight to `Value`'s own conformance — for the dictionary shape that's stdlib `Dictionary`'s order-independent `Hashable`.

Actor types (`ThreadSafeArray`, `ThreadSafeDictionary`, `ThreadSafeAtomic`) don't conform to any of these — `Encodable.encode(to:)`, `==`, and `hash(into:)` are synchronous, but reading actor-isolated state needs `await`. Snapshot manually instead:

```swift
let snapshot = await list.elements
let data = try JSONEncoder().encode(snapshot)
// ...
let restored = ThreadSafeArray(try JSONDecoder().decode([Int].self, from: data))

await list.elements == (await otherList.elements)   // compare the plain snapshots
```

This also rules out `@MainActor`-style isolated conformances: that mechanism ties a conformance to one specific *global* actor, checked statically. `ThreadSafeArray<Element>`/`ThreadSafeDictionary<Key, Value>`/`ThreadSafeAtomic<Value>` are plain `actor` types — each instance is its own isolation domain, so there's no single actor to name, and it wouldn't remove the `await` for a caller outside the isolated instance anyway.

## Testing

```
swift test
```
