# ThreadSafeKit benchmarks

Regenerate (and update the baseline): `swift run -c release ThreadSafeKitBenchmarks --output Benchmarks/RESULTS.md`

## Results

Compared with `Benchmarks/RESULTS.json` from 2026-09-24T19:55:48Z. Percentages are the change from that run. Anything flagged moved more than 30%, beyond both runs' noise, and by more than 5 ns: investigate it before accepting the new numbers.

| Operation                        |        Raw |       actor |        .lock | .readerWriterLock | Spread | vs. baseline |
| -------------------------------- | ---------: | ----------: | -----------: | ----------------: | -----: | ------------ |
| Array count                      |  4.9 (-5%) |  33.6 (-2%) |   18.2 (+5%) |        31.7 (-0%) |    ±3% | ok           |
| Array a[i] get                   |  5.1 (+2%) |  34.1 (-3%) |   44.8 (+0%) |        58.2 (-3%) |    ±3% | ok           |
| Array a[i] = v                   |  2.0 (-1%) |  57.2 (-2%) |   56.4 (-1%) |        69.3 (-4%) |    ±3% | ok           |
| Array a[i] += 1                  |  2.0 (-2%) |  30.2 (-3%) |   56.3 (-3%) |        69.1 (-2%) |    ±3% | ok           |
| Array append + popLast           |  2.5 (-0%) | 123.7 (-0%) |   91.5 (+0%) |       120.1 (+2%) |    ±4% | ok           |
| Dictionary d[k] get              |  9.6 (+1%) |  41.0 (-2%) |   39.7 (-1%) |        53.7 (-2%) |    ±3% | ok           |
| Dictionary d[k] = v              |  6.7 (-2%) |  75.2 (-2%) | 227.9 (-10%) |      242.3 (-12%) |    ±5% | ok           |
| Dictionary d[k]! += 1            |  6.9 (-1%) |  35.0 (-0%) |  231.7 (-8%) |      243.2 (-11%) |    ±4% | ok           |
| Dictionary updateValue           |  7.4 (-0%) |  75.1 (-2%) |   56.3 (-2%) |        72.0 (-0%) |    ±2% | ok           |
| Set contains                     |  8.4 (-3%) |  37.2 (-2%) |   21.4 (-2%) |        35.0 (-2%) |    ±3% | ok           |
| Set insert + remove              | 13.1 (+3%) | 176.5 (-6%) | 128.5 (-38%) |       165.5 (-2%) |    ±7% | ok           |
| Scalar read                      |  1.7 (-4%) |  27.5 (-1%) |   11.2 (-2%) |        24.8 (-2%) |    ±2% | ok           |
| Scalar mutate { += 1 }           |  1.2 (-2%) |  29.7 (-3%) |   10.0 (-2%) |        23.4 (-2%) |    ±3% | ok           |
| Contended 90% read / 10% write   |          - | 250.4 (+0%) |   66.4 (-3%) |      1341.3 (-5%) |    ±6% | ok           |
| Contended 100% read              |          - | 271.5 (+0%) |  104.6 (-6%) |       367.4 (+3%) |    ±6% | ok           |
| Contended 100% write (a[i] += 1) |          - | 279.1 (-1%) |  161.5 (-2%) |      2497.5 (+6%) |    ±4% | ok           |

**0 of 16 operations flagged slower.**

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
| Date | 2026-09-24T20:01:15Z |
| Machine | Mac16,6 |
| CPU | Apple M4 Max |
| Cores | 14 active (10 performance + 4 efficiency) |
| Memory | 36 GB |
| OS | macOS Version 26.6.2 (Build 25G83) |
| Compiler | Swift 6.3, release build |
