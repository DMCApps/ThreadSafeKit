# Design decisions

Approaches that were tried or proposed and then rejected, with the reason for each. Check here before proposing a design change. If a decision is reversed, rewrite or delete its entry.

## `DispatchQueue` as a backing mechanism

- **Tried:** `.dispatchQueue` (concurrent queue, barrier writes), including a parked-barrier `_modify` for subscripts.
- **Rejected because:** `.readerWriterLock` gives the same concurrent-read/exclusive-write semantics at 100–400× less cost on subscript writes. The queue-parking code also caused a thread-pool-exhaustion deadlock and a data race.
- **Instead:** `.lock` or `.readerWriterLock`. Full reasoning is in README "Why not `DispatchQueue`?". Removed in #8.

## Read-only subscripts plus `setElement(_:at:)` on `ThreadSafe`

- **Tried:** removing subscript setters so `ts[i] += 1` couldn't compile, with an explicit setter method instead.
- **Rejected because:** arrays no longer read like arrays; `ts[i] = v` is a core expectation.
- **Instead:** `get` + `_modify` holding the lock across the `yield`, so every subscript access is atomic (#7). The actor `ThreadSafeArray` keeps `setElement(_:at:)`, because actors can't have subscript setters.

## `.readerWriterLock` as the default mechanism

- **Tried:** making `.readerWriterLock` the default, for its concurrent reads.
- **Rejected because:** measured 1.5–30× slower than `.lock` for short operations. It only wins for concurrent scans of about 1,000+ elements.
- **Instead:** `.lock` is the default (#18). See `Benchmarks/RESULTS.md` and README "Which to use".

## `Hashable` conformance

- **Tried:** `ThreadSafe: Hashable where Value: Hashable`, forwarding to the wrapped value.
- **Rejected because:** `ThreadSafe` is a reference type with shared mutable contents, so mutating an instance already stored in a `Set` or used as a `Dictionary` key changes its hash and corrupts the table. Value types avoid this through copy-on-write. The realistic use is `@ThreadSafe var s: Set<Int>`, not `Set<ThreadSafe<Int>>`.
- **Instead:** no `Hashable`; `conformancesAreDeliberate` fails if it's added back. Removed in #2.

## `Codable` conformance

- **Tried:** `ThreadSafe: Codable where Value: Codable`, and snapshot-based encoding for the actors.
- **Rejected because:** decoding silently dropped the chosen mechanism, including one declared on a property wrapper. The actors can only conform to `Decodable` through `@preconcurrency`.
- **Instead:** encode and decode the plain value and wrap it (README "Codable"). Removed in #16; `conformancesAreDeliberate` fails if it's added back.

## Invented helpers (`push`/`pop`, a common `get()`/`set()` on every type)

- **Tried:** queue- and stack-style names, and a uniform `get`/`set` pair across all types.
- **Rejected because:** they aren't how `Array`, `Dictionary` or `Set` behave, so users would have to learn this library's API instead of the standard one.
- **Instead:** only stdlib names and shapes (#10); anything else goes through `mutate`.

## Separate sync classes per shape

- **Tried:** hand-written `ThreadSafeArray` / `ThreadSafeDictionary` / `ThreadSafeAtomic` classes, each with its own copy of the locking code.
- **Rejected because:** three copies of the locking code drift apart; one had already lost its write barrier.
- **Instead:** one `ThreadSafe<Value>` with constrained extensions per shape (#2). Those names now belong to the actors.

## `KeyedStorage` as the dictionary protocol name

- **Tried:** a plainly named public protocol so the dictionary extension could be generic.
- **Rejected because:** a reproduced cross-module ambiguity error when a client module has its own `KeyedStorage`.
- **Instead:** `_ThreadSafeKeyedStorage`, underscored to mark it as implementation detail (#2).

## Conditional `Sendable` (`Value` not required to be `Sendable`)

- **Tried:** `ThreadSafe` being `Sendable` only when `Value: Sendable`.
- **Rejected because:** it forced `withLockUnchecked` throughout, which moves the safety check from the compiler to the author.
- **Instead:** `Value: Sendable` is required everywhere.
