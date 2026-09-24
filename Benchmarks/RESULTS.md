# ThreadSafeKit benchmarks

Regenerate (and update the baseline and README): `swift run -c release ThreadSafeKitBenchmarks --output Benchmarks/RESULTS.md --readme README.md`

## Results

Compared with `Benchmarks/RESULTS.json` from 2026-09-24T20:45:27Z. Percentages are the change from that run. Anything flagged moved more than 30%, beyond both runs' noise, and by more than 5 ns: investigate it before accepting the new numbers.

| Operation                                |         Raw |        actor |       .lock | .readerWriterLock | Spread | vs. baseline |
| ---------------------------------------- | ----------: | -----------: | ----------: | ----------------: | -----: | ------------ |
| Array count                              |   5.3 (+6%) |   34.3 (-3%) |   4.5 (+4%) |        20.8 (+3%) |    ±7% | ok           |
| Array a[i] get                           |   5.2 (+3%) |   35.0 (+0%) |   4.5 (+4%) |        21.0 (+2%) |    ±9% | ok           |
| Array a[i] = v                           |   2.0 (+1%) |   57.2 (-2%) |  30.5 (-0%) |        46.8 (+1%) |    ±3% | ok           |
| Array a[i] += 1                          |   2.0 (-1%) |   30.7 (-1%) |  11.7 (+1%) |        27.7 (+2%) |    ±4% | ok           |
| Array append + popLast                   |   2.5 (+1%) |  124.1 (-0%) |  19.5 (+1%) |        50.6 (-2%) |    ±4% | ok           |
| Array elements snapshot                  |         5.1 |         31.0 |         7.8 |              24.0 |    ±6% | new          |
| Array contains(where:)                   |        21.6 |      2,604.3 |        24.0 |              40.2 |    ±5% | new          |
| Dictionary d[k] get                      |   9.6 (-3%) |   40.5 (-3%) |   8.1 (-2%) |        24.5 (+2%) |    ±5% | ok           |
| Dictionary d[k] = v                      |   7.1 (+0%) |   73.7 (-3%) |  18.2 (-3%) |        34.3 (-1%) |    ±3% | ok           |
| Dictionary d[k]! += 1                    |  6.2 (-18%) |   33.5 (-3%) |  16.8 (-9%) |        32.5 (-6%) |    ±4% | ok           |
| Dictionary d[k, default: 0] += 1         |         9.2 |         33.8 |        17.2 |              32.5 |    ±4% | new          |
| Dictionary updateValue                   |   7.3 (-6%) |   74.0 (-3%) |  13.7 (-1%) |        30.0 (-0%) |    ±4% | ok           |
| Set contains                             |   8.5 (-1%) |   37.4 (-3%) |   7.2 (+1%) |        23.1 (-2%) |    ±4% | ok           |
| Set insert + remove                      | 27.9 (+54%) | 162.7 (-27%) | 27.2 (-27%) |        60.9 (+7%) |    ±6% | ok           |
| Scalar read                              |   1.8 (+0%) |   27.1 (-4%) |   4.2 (-1%) |        20.1 (+1%) |    ±6% | ok           |
| Scalar mutate { += 1 }                   |   1.2 (-1%) |   28.8 (-4%) |   4.0 (+6%) |        19.6 (-2%) |    ±6% | ok           |
| Contended 90% read / 10% write           |           - |  253.6 (-2%) |  46.5 (+4%) |     1,447.9 (+9%) |    ±6% | ok           |
| Contended 100% read                      |           - |  269.7 (-1%) |  43.7 (-3%) |       328.2 (-3%) |    ±4% | ok           |
| Contended 100% write (a[i] += 1)         |           - |  271.7 (-3%) |  77.5 (+5%) |     2,315.9 (+2%) |    ±6% | ok           |
| Contended long read (count(where:), 10k) |           - |    419,092.8 |     8,974.5 |           1,048.7 |    ±5% | new          |
| Contended long read + 10% write          |           - |    380,110.9 |    12,344.5 |           2,846.0 |   ±10% | new          |

**0 of 21 operations flagged slower.**

### Legend

- **Units:** every figure is **nanoseconds per operation (ns/op)**. Lower is better. 1,000 ns = 1 µs.
- **Raw:** the unsynchronized stdlib type (`Array`/`Dictionary`/`Set`/`Int`) on a single thread. Context for what the wrapper adds; not compared against the baseline.
- **actor:** the actor type (`ThreadSafeArray`/`ThreadSafeDictionary`/`ThreadSafeSet`/`ThreadSafeAtomic`), called with `await`. Where it has no direct equivalent it uses the closest API (`a[i] = v` → `setElement`, `+=` → `mutate`, `d[k] = v` → `updateValue`).
- **.lock / .readerWriterLock:** `ThreadSafe<Value>` with that `ThreadSafeMechanism`.
- **Contended rows:** 8 concurrent workers on one shared instance, reported as wall-clock ns per operation. No Raw figure: unsynchronized concurrent access to the raw type would be a data race.
- **How each figure is measured:** the median of 5 whole-suite run(s). Within a run, it's the fastest per-call average over 7 batches, which filters out batches slowed by preemption; the median across runs then ignores an outlier run.
- **Spread:** the largest run-to-run variation in the row (± half of max − min, as a % of the median). A baseline change within that range is likely noise.
- **(+n%) / (−n%):** change from the baseline run. Positive = slower.
- **vs. baseline:** `ok` = nothing moved enough to flag; `⚠️ SLOWER` / `FASTER` = a column moved more than 30%, more than the two runs' combined spread, **and** more than 5 ns; `new` = no baseline figure for this operation. Investigate a ⚠️ before accepting the new numbers. If the change is expected, regenerate with `--output` and commit the results as the new baseline.

## System

| | |
| --- | --- |
| Date | 2026-09-24T23:16:55Z |
| Machine | Mac16,6 |
| CPU | Apple M4 Max |
| Cores | 14 active (10 performance + 4 efficiency) |
| Memory | 36 GB |
| OS | macOS Version 26.6.2 (Build 25G83) |
| Compiler | Swift 6.3, release build |
