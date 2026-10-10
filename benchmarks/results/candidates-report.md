# UUID benchmark: candidates

Times are medians of session medians in ns/operation; sorting is ns/element including an identical input copy. Speedup is old/new. Confidence intervals come from 2000 paired bootstrap resamples per session. MAD is median absolute deviation of ns/operation across all raw samples. Results describe this machine only.

| Variant | Case | Old ns | New ns | New ops/s | Speedup | CI95 range across sessions | Old/new MAD | Sessions |
|---|---|---:|---:|---:|---:|---|---|---:|
| order128 | order_v4/prng | 7.167 | 9.911 | 100,892,940 | 0.726x | [0.702, 0.745] | 0.213/0.325 | 3 |
| order128 | order_v7/prng | 9.990 | 9.996 | 100,042,842 | 0.999x | [0.951, 1.024] | 0.426/0.522 | 3 |
| order128 | order_equal/prng | 11.672 | 9.960 | 100,403,834 | 1.172x | [1.122, 1.237] | 0.627/0.435 | 3 |
| order128 | order_last/prng | 10.886 | 9.500 | 105,262,068 | 1.146x | [1.135, 1.183] | 0.165/0.089 | 3 |
| order128 | sort_v4/prng | 92.493 | 80.737 | 12,385,858 | 1.146x | [1.121, 1.154] | 1.143/1.069 | 3 |
| order128 | sort_v7/prng | 98.377 | 70.185 | 14,248,141 | 1.400x | [1.360, 1.411] | 1.715/1.514 | 3 |
| order64 | order_v4/prng | 6.876 | 2.005 | 498,702,888 | 3.406x | [3.382, 3.452] | 0.103/0.034 | 3 |
| order64 | order_v7/prng | 9.389 | 2.010 | 497,571,461 | 4.672x | [4.627, 4.733] | 0.143/0.029 | 3 |
| order64 | order_equal/prng | 10.889 | 2.491 | 401,420,023 | 4.371x | [4.342, 4.424] | 0.183/0.035 | 3 |
| order64 | order_last/prng | 10.872 | 2.486 | 402,188,217 | 4.361x | [4.306, 4.406] | 0.101/0.025 | 3 |
| order64 | sort_v4/prng | 92.481 | 41.992 | 23,814,029 | 2.204x | [2.176, 2.219] | 1.261/0.378 | 3 |
| order64 | sort_v7/prng | 98.300 | 28.250 | 35,398,738 | 3.475x | [3.454, 3.513] | 1.331/0.306 | 3 |
| parse_fixed | parse_lower/prng | 152.816 | 201.431 | 4,964,476 | 0.760x | [0.752, 0.772] | 1.903/2.412 | 3 |
| parse_fixed | parse_upper/prng | 155.857 | 204.178 | 4,897,696 | 0.763x | [0.759, 0.769] | 1.751/2.210 | 3 |
| parse_fixed | parse_mixed/prng | 154.767 | 202.922 | 4,927,996 | 0.761x | [0.755, 0.767] | 1.391/1.761 | 3 |
| parse_fixed | parse_invalid_early/prng | 3.753 | 6.404 | 156,146,965 | 0.585x | [0.574, 0.592] | 0.078/0.096 | 3 |
| parse_fixed | parse_invalid_late/prng | 144.473 | 191.633 | 5,218,318 | 0.754x | [0.748, 0.759] | 1.401/1.795 | 3 |
| parse_fixed | parse_invalid_dash/prng | 2.118 | 6.405 | 156,121,198 | 0.331x | [0.316, 0.340] | 0.048/0.076 | 3 |
| parse_fixed | parse_invalid_length/prng | 0.542 | 0.543 | 1,840,942,548 | 0.998x | [0.964, 1.017] | 0.005/0.004 | 3 |
| parse_table | parse_lower/prng | 152.573 | 22.150 | 45,147,051 | 6.888x | [6.794, 6.984] | 2.068/0.272 | 3 |
| parse_table | parse_upper/prng | 155.208 | 22.128 | 45,191,154 | 7.014x | [6.966, 7.081] | 2.052/0.282 | 3 |
| parse_table | parse_mixed/prng | 154.266 | 22.229 | 44,987,117 | 6.951x | [6.837, 7.014] | 0.916/0.276 | 3 |
| parse_table | parse_invalid_early/prng | 3.724 | 6.413 | 155,930,991 | 0.579x | [0.573, 0.591] | 0.045/0.086 | 3 |
| parse_table | parse_invalid_late/prng | 144.919 | 13.314 | 75,107,698 | 10.866x | [10.688, 10.953] | 1.355/0.124 | 3 |
| parse_table | parse_invalid_dash/prng | 2.136 | 6.420 | 155,765,766 | 0.330x | [0.317, 0.342] | 0.054/0.058 | 3 |
| parse_table | parse_invalid_length/prng | 0.545 | 0.544 | 1,837,917,507 | 1.001x | [0.990, 1.014] | 0.008/0.007 | 3 |
| hex_pairs | string/prng | 11.041 | 6.828 | 146,465,926 | 1.617x | [1.598, 1.676] | 0.084/0.059 | 3 |
| hex_pairs | format/prng | 18.601 | 12.145 | 82,340,511 | 1.561x | [1.519, 1.589] | 0.261/0.220 | 3 |
| hex_pairs | v4_string/prng | 14.312 | 10.906 | 91,689,670 | 1.311x | [1.293, 1.326] | 0.152/0.096 | 3 |
| hex_pairs | v4_string/io | 34.821 | 25.085 | 39,865,008 | 1.388x | [1.368, 1.402] | 0.368/0.265 | 3 |
| hex_pairs | v7_string/prng | 14.194 | 13.941 | 71,732,438 | 1.020x | [1.005, 1.036] | 0.114/0.103 | 3 |
| hex_pairs | v7_string/io | 50.597 | 42.034 | 23,790,405 | 1.204x | [1.196, 1.214] | 0.533/0.346 | 3 |
| grouped | v7_at/prng | 2.666 | 9.383 | 106,575,348 | 0.284x | [0.282, 0.288] | 0.035/0.086 | 3 |
| grouped | v7_at/io | 41.661 | 25.015 | 39,976,277 | 1.678x | [1.662, 1.690] | 0.342/0.254 | 3 |
| grouped | v7_clock/prng | 42.991 | 39.264 | 25,468,471 | 1.097x | [1.093, 1.106] | 0.364/0.413 | 3 |
| grouped | v7_clock/io | 73.516 | 56.436 | 17,719,168 | 1.303x | [1.294, 1.311] | 0.845/0.508 | 3 |
| grouped | next_fixed/prng | 15.599 | 7.457 | 134,102,385 | 2.045x | [2.027, 2.097] | 0.126/0.066 | 3 |
| grouped | next_fixed/io | 31.733 | 26.500 | 37,735,698 | 1.186x | [1.180, 1.210] | 0.282/0.292 | 3 |
| grouped | next_increasing/prng | 18.530 | 14.399 | 69,450,449 | 1.288x | [1.281, 1.319] | 0.202/0.159 | 3 |
| grouped | next_increasing/io | 48.962 | 26.683 | 37,476,641 | 1.816x | [1.755, 1.892] | 0.716/0.997 | 3 |
| grouped | next_regression/prng | 15.381 | 10.344 | 96,677,347 | 1.489x | [1.481, 1.541] | 0.172/0.096 | 3 |
| grouped | next_regression/io | 31.544 | 26.556 | 37,655,609 | 1.193x | [1.184, 1.218] | 0.306/0.363 | 3 |
| grouped | next_overflow/prng | 19.739 | 12.067 | 82,873,422 | 1.618x | [1.597, 1.643] | 0.353/0.115 | 3 |
| grouped | next_overflow/io | 49.712 | 27.619 | 36,206,628 | 1.784x | [1.774, 1.824] | 0.622/0.445 | 3 |
| grouped | next_clock/prng | 42.722 | 37.840 | 26,427,262 | 1.129x | [1.122, 1.156] | 0.461/0.440 | 3 |
| grouped | next_clock/io | 59.508 | 55.251 | 18,099,063 | 1.072x | [1.059, 1.082] | 0.325/0.380 | 3 |
| grouped | v7_string/prng | 14.200 | 19.003 | 52,623,901 | 0.756x | [0.744, 0.773] | 0.121/0.180 | 3 |
| grouped | v7_string/io | 50.646 | 34.718 | 28,803,307 | 1.459x | [1.418, 1.512] | 0.851/0.467 | 3 |

## Acceptance gates

Require >=5% time reduction and CI95 lower bound >1 in the primary case in all three sessions; reject any applicable case with >3% median time regression in any session.

- **order: order64**
  - order128: order_v4/prng session 1: regression 37.7%; order_v4/prng session 2: regression 38.3%; order_v4/prng session 3: regression 37.3%; primary case does not improve time by >=5% with CI excluding parity in all sessions
  - order64: accepted
- **parse: old**
  - parse_fixed: parse_lower/prng session 1: regression 31.5%; parse_lower/prng session 2: regression 31.6%; parse_lower/prng session 3: regression 31.8%; parse_upper/prng session 1: regression 30.5%; parse_upper/prng session 2: regression 31.0%; parse_upper/prng session 3: regression 31.2%; parse_mixed/prng session 1: regression 31.4%; parse_mixed/prng session 2: regression 31.7%; parse_mixed/prng session 3: regression 30.8%; parse_invalid_early/prng session 1: regression 70.8%; parse_invalid_early/prng session 2: regression 70.3%; parse_invalid_early/prng session 3: regression 71.0%; parse_invalid_late/prng session 1: regression 32.8%; parse_invalid_late/prng session 2: regression 32.6%; parse_invalid_late/prng session 3: regression 32.7%; parse_invalid_dash/prng session 1: regression 197.6%; parse_invalid_dash/prng session 2: regression 205.6%; parse_invalid_dash/prng session 3: regression 202.4%; primary case does not improve time by >=5% with CI excluding parity in all sessions
  - parse_table: parse_invalid_early/prng session 1: regression 72.7%; parse_invalid_early/prng session 2: regression 72.2%; parse_invalid_early/prng session 3: regression 72.7%; parse_invalid_dash/prng session 1: regression 203.1%; parse_invalid_dash/prng session 2: regression 206.0%; parse_invalid_dash/prng session 3: regression 200.3%
- **format: hex_pairs**
  - hex_pairs: accepted
- **stateless_rng: old**
  - grouped: v7_at/prng session 1: regression 250.0%; v7_at/prng session 2: regression 254.4%; v7_at/prng session 3: regression 251.9%; v7_string/prng session 1: regression 31.9%; v7_string/prng session 2: regression 33.8%; v7_string/prng session 3: regression 32.3%
- **generator_rng: grouped**
  - grouped: accepted
