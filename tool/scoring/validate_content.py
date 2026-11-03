"""Reject stale scoring annotations before generating or publishing content."""
import argparse
import json
import math
from pathlib import Path
from fingerprint import DIFFICULTIES, input_hash, tier_for


def validate(songs, steps, previous=None):
    problems, rated, available = [], set(), set()
    for path in sorted(Path(songs).glob('*.json')):
        song = json.loads(path.read_text())
        name = song['name']
        block = song.get('scoring_tiers')
        for diff, level in song.get('sp', {}).items():
            if level is not None and 1 <= level <= 19:
                available.add((name, diff))
        if block is None:
            continue
        try:
            if block['schema'] != 1 or not block['model'] or not block['engine']:
                raise ValueError('Unsupported scoring metadata')
            if block.get('dp'):
                raise ValueError('This release supports SP only')
            data = json.loads((Path(steps)/path.name).read_text())
            for diff, entry in block.get('sp', {}).items():
                if diff not in DIFFICULTIES or (name, diff) not in available:
                    raise ValueError(f'No official chart for {diff}')
                level = song['sp'][diff]
                if not math.isfinite(entry['position']) or tier_for(level, entry['position']) != entry['tier']:
                    raise ValueError(f'Invalid tier for {diff}')
                expected = input_hash(song, data, diff, block['model'], block['engine'])
                if entry['input_hash'] != expected:
                    raise ValueError(f'Stale scoring tier for {diff}; run make tiers')
                rated.add((name, diff))
        except (KeyError, TypeError, ValueError, OSError) as e:
            problems.append(f'{name}: {e}')
    if previous:
        old = json.loads(Path(previous).read_text())
        for song in old:
            block = song.get('scoring_tiers', {})
            for diff in block.get('sp', {}):
                key = (song['name'], diff)
                if key in available and key not in rated:
                    problems.append(f'{key}: previously rated chart lost coverage')
    return dict(available=len(available), rated=len(rated), missing=len(available-rated), problems=problems)

if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--songs', type=Path, required=True)
    p.add_argument('--steps', type=Path, required=True)
    p.add_argument('--previous', type=Path)
    a = p.parse_args()
    result = validate(a.songs, a.steps, a.previous)
    print(json.dumps(result, indent=2))
    raise SystemExit(bool(result['problems']))
