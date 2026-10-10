# UUID benchmark: final

Times are medians of session medians in ns/operation; sorting is ns/element including an identical input copy. Speedup is old/new. Confidence intervals come from 2000 paired bootstrap resamples per session. MAD is median absolute deviation of ns/operation across all raw samples. Results describe this machine only.

| Variant | Case | Old ns | New ns | New ops/s | Speedup | CI95 range across sessions | Old/new MAD | Sessions |
|---|---|---:|---:|---:|---:|---|---|---:|
| current | v7_string/prng | 14.186 | 13.999 | 71,435,526 | 1.016x | [0.984, 1.021] | 0.058/0.106 | 3 |
| current | v7_string/io | 50.520 | 42.107 | 23,748,916 | 1.201x | [1.160, 1.206] | 0.159/0.350 | 3 |
