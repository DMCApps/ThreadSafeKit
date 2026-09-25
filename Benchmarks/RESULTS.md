# ThreadSafeKit benchmarks

Regenerate (and update the baseline and README): `swift run -c release ThreadSafeKitBenchmarks --output Benchmarks/RESULTS.md --readme README.md`

## Results

Compared with `Benchmarks/RESULTS.json` from 2026-09-24T23:29:02Z. Percentages are the change from that run. Anything flagged moved more than 30%, beyond both runs' noise, and by more than 5 ns: investigate it before accepting the new numbers.

| Operation                                |         Raw |          actor |          .lock | .readerWriterLock | Spread | vs. baseline       |
| ---------------------------------------- | ----------: | -------------: | -------------: | ----------------: | -----: | ------------------ |
| Array count                              |   5.7 (+9%) |    24.9 (-30%) |      4.5 (+1%) |        20.1 (+1%) |    ±6% | FASTER: actor -30% |
| Array a[i] get                           |  5.8 (+17%) |    24.4 (-30%) |      4.5 (+2%) |        20.5 (+2%) |    ±4% | ok                 |
| Array a[i] = v                           |   2.0 (+1%) |    29.1 (-48%) |     30.1 (-3%) |        46.0 (-2%) |    ±3% | FASTER: actor -48% |
| Array a[i] += 1                          |   2.0 (+2%) |     29.3 (-3%) |     11.6 (-0%) |        27.5 (+1%) |    ±4% | ok                 |
| Array append + popLast                   |   2.5 (-1%) |    31.4 (-75%) |     19.8 (+4%) |        50.7 (+1%) |    ±3% | FASTER: actor -75% |
| Array elements snapshot                  |  5.9 (+22%) |    27.7 (-11%) |      8.0 (+5%) |        23.5 (-1%) |    ±4% | ok                 |
| Array contains(where:)                   |  22.9 (+8%) |    41.5 (-98%) |     23.5 (-0%) |        40.1 (+2%) |    ±4% | FASTER: actor -98% |
| Dictionary d[k] get                      |   9.5 (-2%) |    32.8 (-21%) |      8.5 (+3%) |        24.7 (+2%) |    ±4% | ok                 |
| Dictionary d[k] = v                      |   6.8 (+2%) |    34.3 (-54%) |     18.5 (+2%) |        34.0 (+1%) |    ±3% | FASTER: actor -54% |
| Dictionary d[k]! += 1                    |   6.1 (+1%) |     32.5 (-2%) |     16.7 (+0%) |        32.6 (+1%) |    ±2% | ok                 |
| Dictionary d[k, default: 0] += 1         |   9.2 (+2%) |     32.7 (-4%) |     17.0 (+1%) |        32.5 (+0%) |    ±2% | ok                 |
| Dictionary updateValue                   |   7.3 (+2%) |    33.1 (-56%) |     13.7 (+0%) |        29.2 (-0%) |    ±4% | FASTER: actor -56% |
| Set contains                             |   8.7 (+1%) |    27.4 (-26%) |      7.2 (+3%) |        23.2 (+1%) |    ±3% | ok                 |
| Set insert + remove                      | 12.6 (-31%) |    67.6 (-66%) |     25.7 (-3%) |       55.7 (-21%) |    ±2% | FASTER: actor -66% |
| Scalar read                              |   1.8 (+4%) |    24.3 (-12%) |      4.3 (-4%) |        20.2 (+4%) |    ±4% | ok                 |
| Scalar mutate { += 1 }                   |   1.3 (+1%) |    24.0 (-15%) |      3.8 (-5%) |        19.7 (+1%) |    ±8% | ok                 |
| Contended 90% read / 10% write           |           - |    236.0 (-8%) |     48.7 (-0%) |     1,425.6 (+8%) |    ±8% | ok                 |
| Contended 100% read                      |           - |    261.8 (-5%) |     43.7 (-7%) |       325.8 (-4%) |   ±12% | ok                 |
| Contended 100% write (a[i] += 1)         |           - |    16.9 (-94%) |     80.0 (+1%) |     2,295.6 (+1%) |    ±3% | FASTER: actor -94% |
| Contended long read (count(where:), 64)  |           - |   283.3 (-93%) |    150.5 (+3%) |       385.6 (+2%) |    ±3% | FASTER: actor -93% |
| Contended long read (count(where:), 256) |           - |   373.8 (-97%) |   452.6 (+19%) |       366.5 (-0%) |   ±11% | FASTER: actor -97% |
| Contended long read (count(where:), 1k)  |           - |   654.8 (-99%) |  1,098.1 (-0%) |       309.7 (+1%) |    ±7% | FASTER: actor -99% |
| Contended long read (count(where:), 10k) |           - | 4,108.3 (-99%) |  8,504.8 (-8%) |     1,046.6 (+0%) |    ±4% | FASTER: actor -99% |
| Contended long read + 10% write          |           - | 3,627.5 (-99%) | 12,353.6 (-7%) |     2,997.9 (+8%) |   ±10% | FASTER: actor -99% |
| Contended long read + 50% write          |           - | 2,127.8 (-99%) |  6,879.3 (-6%) |     3,436.8 (-8%) |    ±9% | FASTER: actor -99% |

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
| Date | 2026-09-25T01:56:19Z |
| Machine | Mac16,6 |
| CPU | Apple M4 Max |
| Cores | 14 active (10 performance + 4 efficiency) |
| Memory | 36 GB |
| OS | macOS Version 26.6.2 (Build 25G83) |
| Compiler | Swift 6.3, release build |
