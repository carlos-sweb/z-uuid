#!/usr/bin/env python3
"""Summarize paired benchmark sessions and apply the predeclared acceptance gates."""
import argparse
from collections import defaultdict
import json
from pathlib import Path
import statistics

GROUPS = {
    'order': ({'order128', 'order64'}, {'order_v4', 'order_v7', 'order_equal', 'order_last', 'sort_v4', 'sort_v7'}, ('order_v7', 'prng')),
    'parse': ({'parse_fixed', 'parse_table'}, {'parse_lower', 'parse_upper', 'parse_mixed', 'parse_invalid_early', 'parse_invalid_late', 'parse_invalid_dash', 'parse_invalid_length'}, ('parse_lower', 'prng')),
    'format': ({'hex_pairs'}, {'string', 'format', 'v4_string', 'v7_string'}, ('string', 'prng')),
    'stateless_rng': ({'grouped'}, {'v7_at', 'v7_clock', 'v7_string'}, ('v7_at', 'io')),
    'generator_rng': ({'grouped'}, {'next_fixed', 'next_increasing', 'next_regression', 'next_overflow', 'next_clock'}, ('next_increasing', 'io')),
}

def load(directory, suite):
    rows = defaultdict(list)
    for path in sorted(directory.glob(f'{suite}-[0-9]*.jsonl')):
        for line in path.read_text().splitlines():
            event = json.loads(line)
            if event['type'] == 'case':
                event['session'] = int(path.stem.rsplit('-', 1)[1])
                rows[(event['variant'], event['work'], event['source'])].append(event)
    return rows

def median_abs_deviation(values):
    center = statistics.median(values)
    return statistics.median(abs(x - center) for x in values)

def evaluate(rows, sizes):
    decisions = {}
    for group, (variants, works, primary) in GROUPS.items():
        candidates = []
        for variant in sorted(variants):
            subset = {key: samples for key, samples in rows.items() if key[0] == variant and key[1] in works}
            reasons = []
            for work in works:
                sources = ('prng', 'io') if work.startswith('v7_') or work.startswith('next_') or work == 'v4_string' else ('prng',)
                for source in sources:
                    if (variant, work, source) not in subset:
                        reasons.append(f'{work}/{source}: missing case')
            for key, samples in subset.items():
                if len(samples) != 3:
                    reasons.append(f'{key[1]}/{key[2]}: expected three sessions')
                for sample in samples:
                    if sample['speedup'] < 1 / 1.03:
                        reasons.append(f"{key[1]}/{key[2]} session {sample['session']}: regression {(1/sample['speedup']-1)*100:.1f}%")
            main = subset.get((variant, *primary), [])
            if len(main) != 3:
                reasons.append('primary case missing sessions')
            elif not all(s['speedup'] >= 1 / .95 and s['ci95'][0] > 1 for s in main):
                reasons.append('primary case does not improve time by >=5% with CI excluding parity in all sessions')
            candidates.append({'variant': variant, 'accepted': not reasons,
                               'primary_speedup': statistics.median(s['speedup'] for s in main) if main else None,
                               'reasons': reasons})
        accepted = [c for c in candidates if c['accepted']]
        accepted.sort(key=lambda c: c['primary_speedup'], reverse=True)
        winner = accepted[0]['variant'] if accepted else 'old'
        if len(accepted) > 1:
            tied = [candidate for candidate in accepted if accepted[0]['primary_speedup'] / candidate['primary_speedup'] < 1.03]
            if len(tied) > 1:
                if not all(candidate['variant'] in sizes for candidate in tied):
                    raise SystemExit('Run benchmarks/sizes.py before resolving a performance tie')
                winner = min(tied, key=lambda candidate: (sizes[candidate['variant']]['total_bytes'], -candidate['primary_speedup']))['variant']
        decisions[group] = {'winner': winner, 'candidates': candidates}
    return decisions

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, default=Path(__file__).parent / 'results')
    parser.add_argument('--suite', choices=('candidates', 'final'), default='final')
    args = parser.parse_args()
    rows = load(args.directory, args.suite)
    if not rows:
        raise SystemExit('No case data found')
    lines = [f'# UUID benchmark: {args.suite}', '',
             'Times are medians of session medians in ns/operation; sorting is ns/element including an identical input copy. '
             'Speedup is old/new. Confidence intervals come from 2000 paired bootstrap resamples per session. '
             'MAD is median absolute deviation of ns/operation across all raw samples. Results describe this machine only.', '',
             '| Variant | Case | Old ns | New ns | New ops/s | Speedup | CI95 range across sessions | Old/new MAD | Sessions |',
             '|---|---|---:|---:|---:|---:|---|---|---:|']
    for (variant, work, source), samples in rows.items():
        old = statistics.median(s['old_ns'] for s in samples)
        new = statistics.median(s['new_ns'] for s in samples)
        speedup = statistics.median(s['speedup'] for s in samples)
        lower = min(s['ci95'][0] for s in samples)
        upper = max(s['ci95'][1] for s in samples)
        old_mad = median_abs_deviation([v for s in samples for v in s['old_samples']])
        new_mad = median_abs_deviation([v for s in samples for v in s['new_samples']])
        lines.append(f'| {variant} | {work}/{source} | {old:.3f} | {new:.3f} | {1e9/new:,.0f} | {speedup:.3f}x | [{lower:.3f}, {upper:.3f}] | {old_mad:.3f}/{new_mad:.3f} | {len(samples)} |')
    if args.suite == 'candidates':
        sizes_path = args.directory / "sizes.json"
        sizes = json.loads(sizes_path.read_text()) if sizes_path.exists() else {}
        decisions = evaluate(rows, sizes)
        (args.directory / 'decisions.json').write_text(json.dumps(decisions, indent=2) + '\n')
        lines.extend(['', '## Acceptance gates', '', 'Require >=5% time reduction and CI95 lower bound >1 in the primary case in all three sessions; reject any applicable case with >3% median time regression in any session.', ''])
        for group, decision in decisions.items():
            lines.append(f"- **{group}: {decision['winner']}**")
            for candidate in decision['candidates']:
                lines.append(f"  - {candidate['variant']}: " + ('accepted' if candidate['accepted'] else '; '.join(candidate['reasons'])))
    destination = args.directory / f'{args.suite}-report.md'
    destination.write_text('\n'.join(lines) + '\n')
    print(destination)
    if args.suite == 'candidates':
        for group, decision in decisions.items():
            print(f"{group}: {decision['winner']}")

if __name__ == '__main__':
    main()
