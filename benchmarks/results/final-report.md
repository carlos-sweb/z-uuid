# UUID benchmark: final

Times are medians of session medians in ns/operation; sorting is ns/element including an identical input copy. Speedup is old/new. Confidence intervals come from 2000 paired bootstrap resamples per session. MAD is median absolute deviation of ns/operation across all raw samples. Results describe this machine only.

| Variant | Case | Old ns | New ns | New ops/s | Speedup | CI95 range across sessions | Old/new MAD | Sessions |
|---|---|---:|---:|---:|---:|---|---|---:|
| current | v4/prng | 2.228 | 2.232 | 448,030,948 | 0.996x | [0.990, 1.004] | 0.013/0.013 | 3 |
| current | v4/io | 25.466 | 25.474 | 39,255,002 | 0.999x | [0.993, 1.006] | 0.161/0.197 | 3 |
| current | v7_at/prng | 2.647 | 2.643 | 378,325,603 | 1.000x | [0.995, 1.005] | 0.009/0.008 | 3 |
| current | v7_at/io | 41.975 | 41.932 | 23,848,206 | 1.001x | [0.998, 1.005] | 0.141/0.182 | 3 |
| current | v7_clock/prng | 43.163 | 43.090 | 23,207,455 | 1.001x | [0.998, 1.010] | 0.145/0.140 | 3 |
| current | v7_clock/io | 73.422 | 73.365 | 13,630,570 | 1.000x | [0.997, 1.006] | 0.637/0.493 | 3 |
| current | next_fixed/prng | 15.201 | 7.468 | 133,907,531 | 2.035x | [2.026, 2.106] | 0.142/0.027 | 3 |
| current | next_fixed/io | 31.254 | 26.394 | 37,887,360 | 1.185x | [1.178, 1.190] | 0.107/0.091 | 3 |
| current | next_increasing/prng | 18.534 | 14.686 | 68,092,140 | 1.263x | [1.258, 1.277] | 0.115/0.079 | 3 |
| current | next_increasing/io | 48.488 | 26.059 | 38,373,983 | 1.862x | [1.844, 1.871] | 0.196/0.175 | 3 |
| current | next_regression/prng | 15.439 | 10.591 | 94,419,244 | 1.456x | [1.450, 1.505] | 0.145/0.027 | 3 |
| current | next_regression/io | 31.542 | 26.406 | 37,870,608 | 1.195x | [1.162, 1.198] | 0.164/0.131 | 3 |
| current | next_overflow/prng | 19.508 | 12.042 | 83,045,981 | 1.620x | [1.615, 1.666] | 0.162/0.041 | 3 |
| current | next_overflow/io | 49.855 | 27.396 | 36,501,132 | 1.820x | [1.662, 1.830] | 0.460/0.545 | 3 |
| current | next_clock/prng | 42.823 | 37.771 | 26,474,990 | 1.136x | [1.130, 1.149] | 0.219/0.121 | 3 |
| current | next_clock/io | 58.972 | 55.751 | 17,936,776 | 1.060x | [1.035, 1.071] | 0.259/0.358 | 3 |
| current | order_v4/prng | 6.348 | 2.002 | 499,550,660 | 3.157x | [3.031, 3.183] | 0.032/0.019 | 3 |
| current | order_v7/prng | 11.935 | 2.008 | 497,885,290 | 5.941x | [5.725, 5.982] | 0.060/0.020 | 3 |
| current | order_equal/prng | 13.960 | 2.485 | 402,361,526 | 5.620x | [5.599, 5.650] | 0.058/0.010 | 3 |
| current | order_last/prng | 13.979 | 2.492 | 401,328,536 | 5.625x | [5.523, 5.903] | 0.101/0.020 | 3 |
| current | eql/prng | 1.478 | 1.480 | 675,488,786 | 1.000x | [0.994, 1.005] | 0.011/0.010 | 3 |
| current | version/prng | 0.791 | 0.755 | 1,324,908,796 | 1.039x | [1.003, 1.069] | 0.024/0.005 | 3 |
| current | string/prng | 11.152 | 6.831 | 146,394,578 | 1.615x | [1.504, 1.729] | 0.164/0.075 | 3 |
| current | format/prng | 18.660 | 12.067 | 82,869,433 | 1.555x | [1.448, 1.565] | 0.124/0.156 | 3 |
| current | parse_lower/prng | 153.058 | 152.968 | 6,537,312 | 0.999x | [0.993, 1.004] | 0.698/0.648 | 3 |
| current | parse_upper/prng | 155.122 | 154.036 | 6,491,981 | 1.008x | [1.004, 1.013] | 0.687/0.834 | 3 |
| current | parse_mixed/prng | 153.953 | 153.843 | 6,500,139 | 1.001x | [0.997, 1.006] | 0.387/0.693 | 3 |
| current | parse_invalid_early/prng | 3.702 | 3.671 | 272,393,469 | 1.008x | [0.998, 1.025] | 0.030/0.017 | 3 |
| current | parse_invalid_late/prng | 145.331 | 144.939 | 6,899,472 | 1.002x | [0.997, 1.007] | 0.464/0.716 | 3 |
| current | parse_invalid_dash/prng | 2.133 | 2.173 | 460,222,203 | 0.982x | [0.933, 1.003] | 0.050/0.008 | 3 |
| current | parse_invalid_length/prng | 0.545 | 0.542 | 1,843,510,843 | 1.003x | [0.998, 1.012] | 0.003/0.003 | 3 |
| current | v4_string/prng | 14.251 | 10.915 | 91,620,399 | 1.302x | [1.246, 1.435] | 0.122/0.066 | 3 |
| current | v4_string/io | 34.877 | 25.119 | 39,811,280 | 1.388x | [1.382, 1.416] | 0.217/0.114 | 3 |
| current | v7_string/prng | 14.211 | 13.988 | 71,489,594 | 1.016x | [0.969, 1.039] | 0.108/0.147 | 3 |
| current | v7_string/io | 50.580 | 42.231 | 23,679,486 | 1.201x | [1.155, 1.206] | 0.193/0.351 | 3 |
| current | sort_v4/prng | 67.581 | 41.662 | 24,002,794 | 1.625x | [1.616, 1.631] | 0.290/0.193 | 3 |
| current | sort_v7/prng | 115.241 | 28.052 | 35,648,542 | 4.114x | [4.096, 4.137] | 0.511/0.126 | 3 |
