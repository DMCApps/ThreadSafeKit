# ThreadSafeKit

Thread-safe wrapper types for Swift 6+ strict concurrency. Each type is `Sendable`, so mutable state pass across isolation domains without data races, no manual locking at call site.

## Requirements

- Swift 6.3+ tools, `swiftLanguageModes: [.v6]`
- iOS 17+, tvOS 17+, macOS 14+

## Install

```swift
.package(url: "<repo-url>", from: "1.0.0")
```

## Types

Three storage kinds (single value, array, dictionary), each with two backends:

| Kind | Actor (async) | Lock/queue (sync) |
|---|---|---|
| Single value | `AtomicActor<Value>` | `ThreadSafeAtomic<Value>` (property wrapper) |
| Array | `ArrayActor<Element>` | `ThreadSafeArray<Element>` |
| Dictionary | `DictionaryActor<Key, Value>` | `ThreadSafeDictionary<Key, Value>` |

**Actor types** — `AtomicActor`, `ArrayActor`, `DictionaryActor`: real actors, isolated by Swift's runtime. Access needs `await`. No lock contention, safe under strict concurrency by construction.

**Sync types** — `ThreadSafeAtomic`/`ThreadSafeArray`/`ThreadSafeDictionary`: no `await` needed, useful where sync access is required (e.g. a property wrapper on a non-async type). Each takes a `mechanism: ThreadSafeMechanism` parameter (default `.dispatchQueue`) picking the backing: `.lock` (`OSAllocatedUnfairLock`, real/checked `Sendable`) or `.dispatchQueue` (serial queue for `ThreadSafeAtomic`, concurrent queue + barrier writes for `ThreadSafeArray`/`ThreadSafeDictionary`; `@unchecked Sendable` — safety enforced internally, not by the compiler). Actor types don't take a mechanism — actor isolation always requires `await`, so there's no sync/mechanism choice to make.

When the wrapped `Value`/`Element`/`Key`+`Value` is `Codable`, so is the sync wrapper itself (`ThreadSafeAtomic`, `ThreadSafeArray`, `ThreadSafeDictionary`), regardless of mechanism. Same for `Equatable` and `Hashable`. Actor types are intentionally none of these — all three require synchronous access (`Encodable.encode(to:)`, `==`, `hash(into:)`) but reading actor-isolated state needs `await`; snapshot via `get()`/`elements`/`dictionary` and restore via `init(_:)`/compare or hash the plain value at the call site instead.

Sync types also conform to `CustomStringConvertible` unconditionally — `description` prints the wrapper name plus its current contents (e.g. `ThreadSafeAtomic(42)`, `ThreadSafeArray([1, 2, 3])`), useful in `print`/`po`. Actor types don't get this either, for the same synchronous-access reason.

All mutation goes through `mutate(_:)` (or dedicated methods like `append`/`setValue`) — direct assignment to `wrappedValue`/`value` is unavailable, since read-modify-write isn't atomic across two separate lock acquisitions.

### When to use which

| Type | Backend | Use when |
|---|---|---|
| `ThreadSafeAtomic<Value>` | `.lock` (unfair lock) or `.dispatchQueue` (serial queue, default), property wrapper | Sync single-value state (counters, flags, config snapshots); pick `.lock` for low-contention short critical sections, `.dispatchQueue` for queue semantics (FIFO ordering, QoS control). |
| `AtomicActor<Value>` | actor | Single-value state owned by async code; callers already `await`. |
| `ThreadSafeArray<Element>` | `.lock` (unfair lock) or `.dispatchQueue` (concurrent + barrier, default) | Sync array access from non-async code; pick `.lock` for low-contention short critical sections, `.dispatchQueue` for many concurrent reads with occasional writes. |
| `ArrayActor<Element>` | actor | Array state owned by async code. |
| `ThreadSafeDictionary<Key, Value>` | `.lock` (unfair lock) or `.dispatchQueue` (concurrent + barrier, default) | Sync dictionary/cache access from non-async code; pick `.lock` for low-contention short critical sections, `.dispatchQueue` for many concurrent reads with occasional writes. |
| `DictionaryActor<Key, Value>` | actor | Dictionary/cache state owned by async code. |

## Usage

```swift
@ThreadSafeAtomic var counter = 0
counter.mutate { $0 += 1 }

let cache = ThreadSafeAtomic(wrappedValue: [String: Int](), mechanism: .lock)
cache.mutate { $0["key"] = 1 }

let list = ArrayActor<Int>()
await list.append(1)
let all = await list.elements

let dict = ThreadSafeDictionary<String, Int>()
dict.setValue(1, forKey: "a")
```

Pick actor types when the caller is already async; pick lock/queue types when it isn't.

### Compound operations with `mutate`

Every type's individual calls (`append`, `setValue`, subscripts, …) are atomic on their own, but two separate calls are not atomic *together* — a read followed by a write can race with another caller's write in between:

```swift
// NOT safe: another writer can slip in between these two calls
if await dict.getValue(forKey: "x") == nil {
    await dict.setValue(1, forKey: "x")
}
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

counter.mutate { $0 += 1 }   // ThreadSafeAtomic already worked this way, regardless of mechanism
```

**What this does and doesn't fix.** Every type here is already fully thread-safe — no data races, no memory corruption, no crashes, on any single call, with or without `mutate`. The bug `mutate` fixes is a different, narrower one: a *logical* race (check-then-act / TOCTOU) that shows up when a correct outcome depends on two or more calls happening as one step. That race is a bug in your call sequence, not in the underlying storage — but you need `mutate` to close it, since there's no other way to hold the lock/actor across multiple steps. `mutate` doesn't add thread safety that was missing; it adds the ability to make a multi-step operation indivisible.

### Codable, Equatable, and Hashable

Sync types conform conditionally — only when the wrapped type does — regardless of `mechanism`:

```swift
let counter = ThreadSafeAtomic(wrappedValue: 42)
let data = try JSONEncoder().encode(counter)
let decoded = try JSONDecoder().decode(ThreadSafeAtomic<Int>.self, from: data)

let cache = ThreadSafeDictionary(["a": 1])
cache == ThreadSafeDictionary(["a": 1])   // true

let seen: Set<ThreadSafeArray<Int>> = [ThreadSafeArray([1, 2]), ThreadSafeArray([1, 2])]   // one element

struct Container: Codable, Equatable, Hashable {
    let items: ThreadSafeArray<Int>   // synthesis works because ThreadSafeArray<Int> is itself Codable/Equatable/Hashable
}
```

`ThreadSafeDictionary`'s `Hashable` combines each key/value pair's hash order-independently (XOR), since `Dictionary` itself has no `Hashable` conformance to delegate to.

Actor types (`AtomicActor`, `ArrayActor`, `DictionaryActor`) don't conform to any of these — `Encodable.encode(to:)`, `==`, and `hash(into:)` are synchronous, but reading actor-isolated state needs `await`. Snapshot manually instead:

```swift
let snapshot = await list.elements
let data = try JSONEncoder().encode(snapshot)
// ...
let restored = ArrayActor(try JSONDecoder().decode([Int].self, from: data))

await list.elements == (await otherList.elements)   // compare the plain snapshots
```

This also rules out `@MainActor`-style isolated conformances: that mechanism ties a conformance to one specific *global* actor, checked statically. `AtomicActor<Value>`/`ArrayActor<Element>`/`DictionaryActor<Key, Value>` are plain `actor` types — each instance is its own isolation domain, so there's no single actor to name, and it wouldn't remove the `await` for a caller outside the isolated instance anyway.

## Testing

```
swift test
```
