"""Check a portable build against chart-only golden outputs from a frozen build."""
import argparse
import json
import tempfile
from pathlib import Path
from cli import generate
from fingerprint import canonical

if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--input', type=Path, required=True)
    p.add_argument('--bundle', type=Path, required=True)
    p.add_argument('--golden', type=Path, required=True,
                   help='JSON predictions: name, difficulty, predicted, position')
    p.add_argument('--cache', type=Path, required=True)
    p.add_argument('--report', type=Path, required=True)
    p.add_argument('--jobs', type=int, default=2)
    p.add_argument('--position-tolerance', type=float, default=1e-9)
    p.add_argument('--derivatives', type=Path)
    p.add_argument('--flutter', default='flutter')
    a = p.parse_args()
    rows = json.loads(a.golden.read_text())
    if isinstance(rows, dict):
        rows = rows['predictions']
    # Use an isolated song overlay: conformance must never annotate source inputs.
    with tempfile.TemporaryDirectory(prefix='scoring-conformance-') as tmp:
        root = Path(tmp)
        (root/'songs').mkdir()
        (root/'steps').symlink_to((a.input/'steps').resolve(), target_is_directory=True)
        for name in sorted({r['name'] for r in rows}):
            (root/'songs'/f'{name}.json').write_bytes((a.input/'songs'/f'{name}.json').read_bytes())
        args = argparse.Namespace(**vars(a))
        args.input, args.song = root, None
        generate(args)
        mismatches = []
        maximum = 0.
        for r in rows:
            song = json.loads((root/'songs'/f"{r['name']}.json").read_text())
            actual = song.get('scoring_tiers', {}).get('sp', {}).get(r['difficulty'])
            if actual is None:
                mismatches.append(dict(name=r['name'], difficulty=r['difficulty'], reason='unavailable'))
                continue
            delta = abs(actual['position']-r['position'])
            maximum = max(maximum, delta)
            if actual['tier'] != round(r['predicted'], 2) or delta > a.position_tolerance:
                mismatches.append(dict(name=r['name'], difficulty=r['difficulty'], actual=actual, expected=r))
        report = dict(charts=len(rows), max_position_difference=maximum, mismatches=mismatches)
        a.report.write_bytes(canonical(report)+b'\n')
        print(json.dumps(dict(charts=len(rows), mismatches=len(mismatches), max_position_difference=maximum)))
        raise SystemExit(bool(mismatches))
