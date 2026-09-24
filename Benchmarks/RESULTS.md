# ThreadSafeKit benchmarks

Regenerate (and update the baseline and README): `swift run -c release ThreadSafeKitBenchmarks --output Benchmarks/RESULTS.md --readme README.md`

## Results

Compared with `Benchmarks/RESULTS.json` from 2026-09-24T23:16:55Z. Percentages are the change from that run. Anything flagged moved more than 30%, beyond both runs' noise, and by more than 5 ns: investigate it before accepting the new numbers.

| Operation                                |         Raw |           actor |          .lock | .readerWriterLock | Spread | vs. baseline |
| ---------------------------------------- | ----------: | --------------: | -------------: | ----------------: | -----: | ------------ |
| Array count                              |   5.3 (-2%) |      35.6 (+4%) |      4.5 (-1%) |        19.9 (-5%) |    ±8% | ok           |
| Array a[i] get                           |   5.0 (-4%) |      34.8 (-1%) |      4.5 (+0%) |        20.2 (-4%) |    ±8% | ok           |
| Array a[i] = v                           |   2.0 (-2%) |      56.1 (-2%) |     30.9 (+1%) |        46.9 (+0%) |    ±5% | ok           |
| Array a[i] += 1                          |   2.0 (-0%) |      30.2 (-2%) |     11.6 (-0%) |        27.3 (-2%) |    ±4% | ok           |
| Array append + popLast                   |   2.5 (-2%) |     124.6 (+0%) |     19.1 (-2%) |        50.2 (-1%) |    ±5% | ok           |
| Array elements snapshot                  |   4.9 (-5%) |      31.2 (+1%) |      7.6 (-2%) |        23.6 (-2%) |    ±8% | ok           |
| Array contains(where:)                   |  21.1 (-2%) |   2,588.5 (-1%) |     23.5 (-2%) |        39.1 (-3%) |    ±5% | ok           |
| Dictionary d[k] get                      |   9.7 (+1%) |      41.5 (+3%) |      8.2 (+1%) |        24.1 (-2%) |    ±3% | ok           |
| Dictionary d[k] = v                      |   6.7 (-5%) |      74.9 (+2%) |     18.2 (-0%) |        33.6 (-2%) |    ±4% | ok           |
| Dictionary d[k]! += 1                    |   6.1 (-2%) |      33.1 (-1%) |     16.6 (-1%) |        32.4 (-0%) |    ±3% | ok           |
| Dictionary d[k, default: 0] += 1         |   9.1 (-2%) |      34.0 (+1%) |     16.8 (-2%) |        32.4 (-0%) |    ±4% | ok           |
| Dictionary updateValue                   |   7.2 (-2%) |      75.5 (+2%) |     13.7 (-1%) |        29.3 (-2%) |    ±4% | ok           |
| Set contains                             |   8.6 (+1%) |      37.3 (-0%) |      7.0 (-3%) |        22.9 (-1%) |    ±4% | ok           |
| Set insert + remove                      | 18.1 (-35%) |    197.1 (+21%) |     26.6 (-2%) |       70.3 (+15%) |   ±11% | ok           |
| Scalar read                              |   1.7 (-4%) |      27.5 (+2%) |      4.4 (+5%) |        19.4 (-3%) |    ±5% | ok           |
| Scalar mutate { += 1 }                   |   1.2 (-0%) |      28.4 (-1%) |      4.0 (-0%) |        19.5 (-1%) |    ±8% | ok           |
| Contended 90% read / 10% write           |           - |     257.7 (+2%) |     48.9 (+5%) |     1,320.6 (-9%) |    ±7% | ok           |
| Contended 100% read                      |           - |     276.7 (+3%) |     47.0 (+8%) |       339.1 (+3%) |    ±4% | ok           |
| Contended 100% write (a[i] += 1)         |           - |     277.8 (+2%) |     79.0 (+2%) |     2,282.7 (-1%) |    ±5% | ok           |
| Contended long read (count(where:), 64)  |           - |         3,826.6 |          146.0 |             378.4 |    ±4% | new          |
| Contended long read (count(where:), 256) |           - |        13,475.7 |          381.3 |             366.7 |   ±14% | new          |
| Contended long read (count(where:), 1k)  |           - |        46,936.5 |        1,099.6 |             307.5 |    ±4% | new          |
| Contended long read (count(where:), 10k) |           - | 421,959.3 (+1%) |  9,235.9 (+3%) |     1,043.0 (-1%) |    ±5% | ok           |
| Contended long read + 10% write          |           - | 378,231.3 (-0%) | 13,252.2 (+7%) |     2,780.1 (-2%) |   ±12% | ok           |
| Contended long read + 50% write          |           - |       210,345.1 |        7,322.0 |           3,728.0 |    ±7% | new          |

**0 of 25 operations flagged slower.**

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
| Date | 2026-09-24T23:29:02Z |
| Machine | Mac16,6 |
| CPU | Apple M4 Max |
| Cores | 14 active (10 performance + 4 efficiency) |
| Memory | 36 GB |
| OS | macOS Version 26.6.2 (Build 25G83) |
| Compiler | Swift 6.3, release build |
