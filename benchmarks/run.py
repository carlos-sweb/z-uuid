#!/usr/bin/env python3
"""Run three independent benchmark processes and retain raw paired samples.

No third-party Python dependencies. Full comparison is intentionally slow.
"""
import argparse
import hashlib
import json
import os
import platform
import shutil
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parent.parent

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--suite', choices=('candidates', 'final'), default='final')
    parser.add_argument('--output', type=Path, default=ROOT / 'benchmarks/results')
    parser.add_argument('--filter', default='')
    parser.add_argument('--min-ms', type=int, default=100)
    parser.add_argument('--sessions', type=int, default=3)
    args = parser.parse_args()
    if args.sessions < 1 or not 1 <= args.min_ms <= 60000:
        parser.error('sessions must be positive and min-ms must be in [1,60000]')
    baseline = ROOT / 'benchmarks/baseline/uuid.zig'
    provenance = json.loads((baseline.parent / 'provenance.json').read_text())
    if hashlib.sha256(baseline.read_bytes()).hexdigest() != provenance['sha256']:
        raise SystemExit('Frozen baseline hash does not match provenance.json')
    args.output.mkdir(parents=True, exist_ok=True)
    cpu = next((line.split(':', 1)[1].strip() for line in Path('/proc/cpuinfo').read_text().splitlines() if line.startswith('model name')), platform.processor()) if Path('/proc/cpuinfo').exists() else platform.processor()
    environment = {
        'platform': platform.platform(), 'cpu': cpu, 'python': platform.python_version(),
        'zig': subprocess.check_output(['zig', 'version'], text=True).strip(),
        'command': ['zig', 'build', 'bench', '-Doptimize=ReleaseFast', '--', '--json', '--suite', args.suite, '--min-ms', str(args.min_ms)] + (['--filter', args.filter] if args.filter else []),
        'harness_sha256': hashlib.sha256((ROOT / 'benchmarks/main.zig').read_bytes()).hexdigest(),
        'candidates_sha256': hashlib.sha256((ROOT / 'benchmarks/candidates.zig').read_bytes()).hexdigest(),
        'source_sha256': hashlib.sha256((ROOT / 'src/uuid.zig').read_bytes()).hexdigest(),
        'baseline_sha256': hashlib.sha256((ROOT / 'benchmarks/baseline/uuid.zig').read_bytes()).hexdigest(),
        'started_utc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
        'affinity': sorted(os.sched_getaffinity(0)) if hasattr(os, 'sched_getaffinity') else None,
        'filter': args.filter, 'minimum_ms': args.min_ms, 'sessions': args.sessions,
    }
    snapshot = args.output / 'snapshots' / args.suite
    sources = [ROOT / name for name in ('build.zig', 'build.zig.zon', 'mise.toml', 'README.md')]
    sources += list((ROOT / 'src').glob('*.zig')) + list((ROOT / 'tests').glob('*.zig'))
    sources += list((ROOT / 'benchmarks').glob('*.zig')) + list((ROOT / 'benchmarks').glob('*.py'))
    sources += [ROOT / 'benchmarks/README.md'] + list((ROOT / 'benchmarks/baseline').iterdir())
    for source in sources:
        destination = snapshot / source.relative_to(ROOT)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)
    environment['snapshot'] = str(snapshot.relative_to(args.output))
    (args.output / f'{args.suite}-environment.json').write_text(json.dumps(environment, indent=2) + '\n')
    for session in range(1, args.sessions + 1):
        dest = args.output / f'{args.suite}-{session}.jsonl'
        print(f'Session {session}/{args.sessions}: {args.suite}', flush=True)
        with dest.open('w') as output:
            process = subprocess.Popen(environment['command'], cwd=ROOT, stdout=subprocess.PIPE, stderr=None, text=True)
            count = 0
            try:
                for line in process.stdout:
                    output.write(line)
                    output.flush()
                    event = json.loads(line)
                    if event['type'] == 'case':
                        count += 1
                        print(f"  {count}: {event['variant']} {event['work']}/{event['source']} {event['speedup']:.3f}x", flush=True)
            except BaseException:
                process.terminate()
                process.wait()
                raise
            if process.wait() != 0:
                raise SystemExit(f'Benchmark failed; partial data retained in {dest}')
    print('All sessions complete.', flush=True)

if __name__ == '__main__':
    main()
