# ThreadSafeKit benchmarks

ns/op, lower is better; each figure is the minimum per-call average over 7 batches.
Numbers are only comparable between runs on the same machine.

Regenerate: `swift run -c release ThreadSafeKitBenchmarks --output Benchmarks/RESULTS.md`

## Results

| Operation                        |  Raw | actor | .lock | .readerWriterLock | Result                          |
| -------------------------------- | ---: | ----: | ----: | ----------------: | ------------------------------- |
| Array count                      |  5.9 |  35.9 |  15.6 |              28.7 | PASS                            |
| Array a[i] get                   |  4.4 |  32.2 |  40.2 |              54.7 | PASS                            |
| Array a[i] = v                   |  1.9 |  56.2 |  58.0 |              67.1 | PASS                            |
| Array a[i] += 1                  |  1.8 |  28.3 |  53.8 |              67.4 | PASS                            |
| Array append + popLast           |  2.3 | 118.7 |  84.9 |             112.0 | FAIL (.readerWriterLock)        |
| Dictionary d[k] get              |  8.9 |  39.5 |  38.4 |              53.1 | PASS                            |
| Dictionary d[k] = v              |  6.4 |  76.4 | 241.0 |             258.4 | FAIL (.lock, .readerWriterLock) |
| Dictionary d[k]! += 1            |  6.5 |  33.0 | 240.3 |             267.6 | FAIL (.lock, .readerWriterLock) |
| Dictionary updateValue           |  7.1 |  77.5 |  58.9 |              75.9 | PASS                            |
| Set contains                     |  8.2 |  37.6 |  20.9 |              34.1 | PASS                            |
| Set insert + remove              | 16.9 | 168.5 | 159.5 |             158.4 | PASS                            |
| Scalar read                      |  1.6 |  25.2 |  11.0 |              23.7 | PASS                            |
| Scalar mutate { += 1 }           |  1.1 |  29.0 |   9.2 |              22.5 | PASS                            |
| Contended 90% read / 10% write   |    - | 250.5 |  62.0 |            1340.2 | FAIL (.readerWriterLock)        |
| Contended 100% read              |    - | 273.5 |  99.0 |             347.0 | PASS                            |
| Contended 100% write (a[i] += 1) |    - | 284.4 | 168.5 |            2500.9 | FAIL (.readerWriterLock)        |

**11/16 PASS**

## System

Numbers depend heavily on the machine, so compare them only against runs on the same system.

| | |
| --- | --- |
| Date | 2026-09-24T19:51:29Z |
| Machine | Mac16,6 |
| CPU | Apple M4 Max |
| Cores | 14 active (10 performance + 4 efficiency) |
| Memory | 36 GB |
| OS | macOS Version 26.6.2 (Build 25G83) |
| Compiler | Swift 6.3, release build |

## Criteria

- **Raw** is the unsynchronized stdlib type (`Array`/`Dictionary`/`Set`/`Int`) on a single thread.
- **Single-thread:** `.lock` / `.readerWriterLock` ≤ max(Raw × 25, 100 ns); actor ≤ max(Raw × 50, 250 ns).
- **Contended:** every column ≤ 1000 ns/op wall-clock with 8 concurrent workers. No Raw baseline: unsynchronized concurrent access to the raw type would be a data race.
- The actor column uses the actor's equivalent API where there's no direct one (`a[i] = v` → `setElement`, `+=` → `mutate`, `d[k] = v` → `updateValue`).
