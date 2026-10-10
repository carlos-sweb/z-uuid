#!/usr/bin/env python3
"""Compile uniform ReleaseFast wrappers and report text/read-only section sizes."""
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parent.parent
VARIANTS = ('old', 'current', 'order128', 'order64', 'parse_fixed', 'parse_table', 'hex_pairs', 'grouped', 'grouped_policy')

def main():
    results = {}
    for variant in VARIANTS:
        command = ['zig', 'build', 'bench-size', '-Doptimize=ReleaseFast', f'-Dsize-variant={variant}']
        subprocess.run(command, cwd=ROOT, check=True)
        obj = ROOT / f'zig-out/benchmarks/size-{variant}.o'
        listing = subprocess.check_output(['size', '-A', str(obj)], text=True)
        sections = {}
        for line in listing.splitlines():
            fields = line.split()
            if len(fields) >= 2 and fields[0].startswith('.'):
                sections[fields[0]] = int(fields[1])
        text = sum(value for name, value in sections.items() if name.startswith('.text'))
        rodata = sum(value for name, value in sections.items() if name.startswith('.rodata'))
        results[variant] = {'text_bytes': text, 'rodata_bytes': rodata, 'total_bytes': text + rodata, 'sections': sections, 'command': command}
        print(f'{variant}: text={text}, rodata={rodata}, total={text+rodata}', flush=True)
    output = ROOT / 'benchmarks/results/sizes.json'
    output.write_text(json.dumps(results, indent=2) + '\n')

if __name__ == '__main__':
    main()
