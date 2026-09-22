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
| Single value | `AtomicActor<Value>` | `Atomic<Value>` (lock, property wrapper), `AtomicQueue<Value>` (serial queue, property wrapper) |
| Array | `ArrayActor<Element>` | `ArrayQueue<Element>` (concurrent queue, barrier writes) |
| Dictionary | `DictionaryActor<Key, Value>` | `DictionaryQueue<Key, Value>` (concurrent queue, barrier writes) |

**Actor types** — `AtomicActor`, `ArrayActor`, `DictionaryActor`: real actors, isolated by Swift's runtime. Access needs `await`. No lock contention, safe under strict concurrency by construction.

**Sync types** — `Atomic` (unfair lock), `AtomicQueue` (serial `DispatchQueue`), `ArrayQueue`/`DictionaryQueue` (concurrent `DispatchQueue` + barrier writes): no `await` needed, useful where sync access required (e.g. property wrapper on a non-async type). `@unchecked Sendable` — safety enforced internally, not by the compiler.

All mutation goes through `mutate(_:)` (or dedicated methods like `append`/`setValue`) — direct assignment to `wrappedValue`/`value` is unavailable, since read-modify-write isn't atomic across two separate lock acquisitions.

### When to use which

| Type | Backend | Use when |
|---|---|---|
| `Atomic<Value>` | unfair lock, property wrapper | Sync single-value state guarded by a lock; low-contention, short critical sections (counters, flags, config snapshots). |
| `AtomicQueue<Value>` | serial `DispatchQueue`, property wrapper | Sync single-value state, want queue semantics (e.g. FIFO ordering, QoS control) instead of a raw lock. |
| `AtomicActor<Value>` | actor | Single-value state owned by async code; callers already `await`. |
| `ArrayQueue<Element>` | concurrent `DispatchQueue` + barrier | Sync array access from non-async code; many concurrent reads, occasional writes. |
| `ArrayActor<Element>` | actor | Array state owned by async code. |
| `DictionaryQueue<Key, Value>` | concurrent `DispatchQueue` + barrier | Sync dictionary/cache access from non-async code; many concurrent reads, occasional writes. |
| `DictionaryActor<Key, Value>` | actor | Dictionary/cache state owned by async code. |

## Usage

```swift
@Atomic var counter = 0
counter.mutate { $0 += 1 }

let cache = AtomicQueue(wrappedValue: [String: Int]())
cache.mutate { $0["key"] = 1 }

let list = ArrayActor<Int>()
await list.append(1)
let all = await list.elements

let dict = DictionaryQueue<String, Int>()
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

counter.mutate { $0 += 1 }   // Atomic/AtomicQueue already worked this way
```

**What this does and doesn't fix.** Every type here is already fully thread-safe — no data races, no memory corruption, no crashes, on any single call, with or without `mutate`. The bug `mutate` fixes is a different, narrower one: a *logical* race (check-then-act / TOCTOU) that shows up when a correct outcome depends on two or more calls happening as one step. That race is a bug in your call sequence, not in the underlying storage — but you need `mutate` to close it, since there's no other way to hold the lock/actor across multiple steps. `mutate` doesn't add thread safety that was missing; it adds the ability to make a multi-step operation indivisible.

## Testing

```
swift test
```
