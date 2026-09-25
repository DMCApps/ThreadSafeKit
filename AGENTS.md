# ThreadSafeKit

Swift 6.3 package (`swiftLanguageModes: [.v6]`, iOS 17 / tvOS 17 / macOS 14) of thread-safe wrappers for strict concurrency. Tests use Swift Testing. Pre-1.0 (tagged `0.1.0`), so source-breaking changes are acceptable when justified.

Why it exists: to make threading easier on Apple platforms. `async`/`await` can't be used everywhere, so `@ThreadSafe` gives actor-style safety to ordinary values without `await`. Callers use the wrapped `Array`/`Dictionary`/`Set`/value naturally, and every read and write is atomic. The actors offer the same API for callers that can `await`. Thread safety and speed are the top priorities. Overhead over bare `Array`/`Dictionary`/`Set`/value should mainly be the lock/actor hop itself — not extra allocation, copying or indirection layered on top. README "Which to use" picks between `.lock`, `.readerWriterLock` and the actors.

- `ThreadSafe<Value>`: lock-backed class and property wrapper. Shape-specific API comes from constrained extensions in `ThreadSafe+Collection/Array/Dictionary/Set.swift`.
- `ThreadSafeArray` / `ThreadSafeDictionary` / `ThreadSafeSet` / `ThreadSafeAtomic`: `public final actor`s. Shared members live once in `_ThreadSafeActorStorage` (`ThreadSafeActorStorage.swift`).
- `ThreadSafeMechanism`: `.lock` (`OSAllocatedUnfairLock`, the default) and `.readerWriterLock` (`pthread_rwlock`, via `Utility/ReaderWriterLock.swift`).
- `Utility/ReentrancyTracker.swift`: makes `.readerWriterLock` trap on same-thread reentry. `.lock` traps on its own through `os_unfair_lock`.

## Commands

```
swift build --build-tests
swift test
swift test --sanitize=thread                                          # debug build only; release TSan gives a known false positive (see README Testing)
swift test --skip 'Fast|Bounded|CostDoesNotScaleWithCollectionSize'   # correctness only
swift run -c release ThreadSafeKitBenchmarks                          # compare against Benchmarks/RESULTS.json
swift run -c release ThreadSafeKitBenchmarks --output Benchmarks/RESULTS.md --readme README.md   # regenerate the baseline and the README table
```

## Acceptance bar (every change)

1. `swift build --build-tests`: no new warnings in `Sources/`.
2. `swift test`: fully green.
3. `swift test --sanitize=thread`: zero TSan reports.
4. If performance could be affected, run the benchmark, investigate anything flagged slower, then regenerate `Benchmarks/` and the README table using the tool. Never edit those tables by hand.

Report the test counts. Don't call a task done until all of these pass.

## Design rules

Before proposing a design change (mechanism, conformance, API shape), check `docs/DECISIONS.md` for approaches already tried and rejected.

- Thread safety and speed are the top priorities; when they conflict, safety wins. Every public call is one atomic access. Subscripts use `get` + `_modify` so `ts[i] += 1` and `dict[k]?.append(x)` are atomic. Never split a read-modify-write across two lock acquisitions.
- Where misuse can be caught at compile time, catch it there (e.g. an `@available(*, unavailable)` setter on `wrappedValue`) rather than only documenting it.
- Same-thread reentry into an instance must trap deterministically and never hang, under both mechanisms. Cover each new closure-taking member with an exit test.
- Only mirror the stdlib API: the same names and shapes as `Array`/`Dictionary`/`Set`/`SetAlgebra`/collection protocols. Leave anything uncovered to `mutate`.
- Keep the sync wrappers and the actors in lockstep: a member added to one shape goes on its actor counterpart with the same name and semantics.
- A new member that needs a broader constraint gets a new `extension ThreadSafe where …` block. Don't loosen an existing block. Check for overload ambiguity, since `Set` is both `Collection` and `SetAlgebra` and `Array` is both `RangeReplaceableCollection` and `MutableCollection`.
- Any generic type captured by a closure or stored needs `Sendable`, including `Value.Index` where an index is captured.
- Public members are `@inlinable` and actors are `final`; `SourceConventionTests` enforces both. Whatever an `@inlinable` member touches must be `@usableFromInline`, not `private`.
- Conformances: `Equatable` and `CustomStringConvertible` only; `conformancesAreDeliberate` enforces this.
- No speculative abstractions. Add a protocol, wrapper or generic only when there's a concrete second user today.

## Tests

- Parameterize sync tests over the file-local `private let mechanisms: [ThreadSafeMechanism] = [.lock, .readerWriterLock]` with `@Test(arguments: mechanisms)`. Actor tests are `@Test func …() async throws`.
- Concurrency tests have to be concurrent: use `DispatchQueue.concurrentPerform` and assert exact final values. A single-threaded test proves nothing about races.
- Exit and trap tests go inside `#if os(macOS)` with `await #expect(processExitsWith: .failure)` and `.timeLimit(.minutes(1))`, so a hang fails the test instead of blocking the run.
- Performance tests use `assertFast`, are tagged `.performance`, and have names ending in `Fast`, `Bounded` or `CostDoesNotScaleWithCollectionSize`. They're regression guards, not measurements.
- Follow the existing file's conventions exactly rather than adding a new style.
- Add mechanically checkable conventions to `SourceConventionTests` rather than to this file.

## Comments and docs

- Comments: one sentence maximum, accurate to the current code. Don't explain obvious code, don't write historical notes ("previously…", "was removed"), and don't write multi-line blocks for simple operations.
- The README covers only this library. No general Swift/`Sendable` explanations, and no notes about features that were removed. Update it in the same change as any API change, and keep every snippet compilable.
- After any behaviour change, grep `Sources/`, `Tests/` and `README.md` for stale references.

## Git workflow

- Branch from an up-to-date `main` using a type prefix: `feat/`, `fix/`, `refactor/`, `perf/`, `test/`, `docs/` or `chore/`.
- Use Conventional Commit style (`type(scope): Summary`), and keep commits reasonably scoped.
- Rebase on `main` before opening a PR. Include the acceptance-bar results (test counts, TSan) in the PR description.
- Before asserting anything about runtime behaviour (deadlock vs trap, races, performance), verify it with a real repro or measurement. Don't rely on reasoning alone.
