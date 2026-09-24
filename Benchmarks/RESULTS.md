# ThreadSafeKit benchmarks

Regenerate (and update the baseline and README): `swift run -c release ThreadSafeKitBenchmarks --output Benchmarks/RESULTS.md --readme README.md`

## Results

Compared with `Benchmarks/RESULTS.json` from 2026-09-24T20:01:15Z. Percentages are the change from that run. Anything flagged moved more than 30%, beyond both runs' noise, and by more than 5 ns: investigate it before accepting the new numbers.

| Operation                        |         Raw |        actor |       .lock | .readerWriterLock | Spread | vs. baseline                               |
| -------------------------------- | ----------: | -----------: | ----------: | ----------------: | -----: | ------------------------------------------ |
| Array count                      |   5.0 (+3%) |   35.3 (+5%) |  4.3 (-76%) |       20.2 (-36%) |    ±5% | FASTER: .lock -76%, .readerWriterLock -36% |
| Array a[i] get                   |   5.1 (+0%) |   34.9 (+2%) |  4.3 (-90%) |       20.6 (-65%) |    ±3% | FASTER: .lock -90%, .readerWriterLock -65% |
| Array a[i] = v                   |   2.0 (+1%) |   58.5 (+2%) | 30.6 (-46%) |       46.2 (-33%) |    ±1% | FASTER: .lock -46%, .readerWriterLock -33% |
| Array a[i] += 1                  |   2.0 (+1%) |   31.1 (+3%) | 11.6 (-79%) |       27.2 (-61%) |    ±4% | FASTER: .lock -79%, .readerWriterLock -61% |
| Array append + popLast           |   2.5 (+1%) |  124.5 (+1%) | 19.4 (-79%) |       51.5 (-57%) |    ±3% | FASTER: .lock -79%, .readerWriterLock -57% |
| Dictionary d[k] get              |   9.9 (+3%) |   41.8 (+2%) |  8.3 (-79%) |       24.0 (-55%) |    ±2% | FASTER: .lock -79%, .readerWriterLock -55% |
| Dictionary d[k] = v              |   7.0 (+5%) |   75.9 (+1%) | 18.8 (-92%) |       34.7 (-86%) |    ±2% | FASTER: .lock -92%, .readerWriterLock -86% |
| Dictionary d[k]! += 1            |   7.5 (+9%) |   34.4 (-2%) | 18.4 (-92%) |       34.6 (-86%) |    ±4% | FASTER: .lock -92%, .readerWriterLock -86% |
| Dictionary updateValue           |   7.8 (+6%) |   76.3 (+2%) | 13.9 (-75%) |       30.2 (-58%) |    ±8% | FASTER: .lock -75%, .readerWriterLock -58% |
| Set contains                     |   8.6 (+2%) |   38.5 (+3%) |  7.2 (-66%) |       23.5 (-33%) |    ±3% | FASTER: .lock -66%, .readerWriterLock -33% |
| Set insert + remove              | 18.1 (+38%) | 222.9 (+26%) | 37.5 (-71%) |       57.1 (-66%) |    ±1% | FASTER: .lock -71%, .readerWriterLock -66% |
| Scalar read                      |   1.8 (+4%) |   28.0 (+2%) |  4.3 (-62%) |       19.9 (-20%) |    ±3% | FASTER: .lock -62%                         |
| Scalar mutate { += 1 }           |   1.3 (+1%) |   30.1 (+1%) |  3.8 (-62%) |       20.0 (-15%) |    ±4% | FASTER: .lock -62%                         |
| Contended 90% read / 10% write   |           - |  258.6 (+3%) | 44.9 (-32%) |      1330.3 (-1%) |    ±5% | FASTER: .lock -32%                         |
| Contended 100% read              |           - |  273.3 (+1%) | 44.9 (-57%) |       338.5 (-8%) |    ±4% | FASTER: .lock -57%                         |
| Contended 100% write (a[i] += 1) |           - |  280.7 (+1%) | 74.0 (-54%) |      2262.1 (-9%) |    ±1% | FASTER: .lock -54%                         |

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
| Date | 2026-09-24T20:45:27Z |
| Machine | Mac16,6 |
| CPU | Apple M4 Max |
| Cores | 14 active (10 performance + 4 efficiency) |
| Memory | 36 GB |
| OS | macOS Version 26.6.2 (Build 25G83) |
| Compiler | Swift 6.3, release build |
