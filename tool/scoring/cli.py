"""Attach calculated SP tiers to prep songs, reusing only fresh cached results."""
import argparse
import hashlib
import json
import os
import subprocess
import tempfile
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path
from fingerprint import DIFFICULTIES, canonical, digest, input_hash
from validate_content import validate

ROOT = Path(__file__).resolve().parents[2]


def atomic_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    raw = canonical(data)+b'\n'
    if path.exists() and path.read_bytes() == raw:
        return
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as f:
        f.write(raw)
        temporary = Path(f.name)
    temporary.replace(path)


def check_bundle(bundle):
    manifest = json.loads((bundle/'manifest.json').read_text())
    if manifest['schema'] != 1:
        raise ValueError('Unsupported model bundle')
    for name, expected in manifest['files'].items():
        if Path(name).name != name or hashlib.sha256((bundle/name).read_bytes()).hexdigest() != expected:
            raise ValueError(f'Bundle checksum mismatch: {name}')
    for name, expected in manifest['sources'].items():
        if not (ROOT/name).is_relative_to(ROOT) or hashlib.sha256((ROOT/name).read_bytes()).hexdigest() != expected:
            raise ValueError(f'Feature engine differs from fitted bundle: {name}')
    if manifest['engine'] != digest(dict(sources=manifest['sources'], files=manifest['files'])):
        raise ValueError('Bundle identity mismatch')
    return manifest


_WORKER_SCORER = None

def init_worker(bundle, root, feet):
    from inference import Scorer
    global _WORKER_SCORER
    _WORKER_SCORER = Scorer(bundle, root, feet)


def predict_chart(chart):
    key = (chart['name'], chart['difficulty'])
    try:
        result = {**_WORKER_SCORER.predict(*key), 'input_hash': chart['input_hash']}
        return key, result, None
    except (ValueError, KeyError, IndexError, ZeroDivisionError, AssertionError) as e:
        return key, None, str(e)
    finally:
        _WORKER_SCORER.context.clear()


def generate(args):
    manifest = check_bundle(args.bundle)
    model, engine = manifest['model'], manifest['engine']
    selected = set(args.song or [])
    files = sorted((args.input/'songs').glob('*.json'))
    if selected - {p.stem for p in files}:
        raise ValueError(f'Unknown song IDs: {sorted(selected - {p.stem for p in files})}')
    pending, results, failures, songs = [], {}, [], {}
    for path in files:
        song = json.loads(path.read_text())
        if selected and song['name'] not in selected:
            continue
        if song['name'] != path.stem:
            raise ValueError(f'Song ID differs from filename: {path}')
        songs[song['name']] = (path, song)
        try:
            steps = json.loads((args.input/'steps'/path.name).read_text())
        except (OSError, ValueError) as e:
            steps = None
        for diff in DIFFICULTIES:
            level = song.get('sp', {}).get(diff)
            if level is None or not 1 <= level <= 19:
                continue
            key = (song['name'], diff)
            try:
                fingerprint = input_hash(song, steps, diff, model, engine)
                cache = args.cache/f'{fingerprint}.json'
                if cache.exists():
                    value = json.loads(cache.read_text())
                    if value['input_hash'] != fingerprint:
                        raise ValueError('Cache identity mismatch')
                    results[key] = value
                else:
                    pending.append(dict(name=key[0], difficulty=diff, input_hash=fingerprint))
            except (OSError, KeyError, TypeError, ValueError) as e:
                failures.append(dict(name=key[0], difficulty=diff, reason=str(e)))
    with tempfile.TemporaryDirectory(prefix='ddr-scoring-') as tmp:
        work = Path(tmp)
        assets = work/'assets'
        assets.mkdir()
        for kind in ('songs', 'steps'):
            (assets/kind).symlink_to((args.input/kind).resolve(), target_is_directory=True)
        (assets/'patterns').mkdir()
        chart_file, foot_file = work/'charts.json', work/'feet.json'
        atomic_json(chart_file, pending)
        if pending and args.derivatives is None:
            env = dict(os.environ, SCORING_INPUT=str(args.input.resolve()), SCORING_OUTPUT=str(foot_file), SCORING_CHARTS=str(chart_file))
            subprocess.run([args.flutter, 'test', 'tool/export_scoring_features.dart'], cwd=ROOT, env=env, check=True)
        if pending:
            derivative_file = args.derivatives or foot_file
            metadata = json.loads(Path(str(derivative_file)+'.metadata.json').read_text())
            if metadata['sha256'] != hashlib.sha256(derivative_file.read_bytes()).hexdigest():
                raise ValueError('Derivative checksum mismatch')
            for path in ('lib/models/parity.dart', 'lib/models/pattern_analysis.dart',
                         'lib/models/steps_model.dart', 'tool/export_scoring_features.dart'):
                if metadata['sources'].get(path) != manifest['sources'][path]:
                    raise ValueError('Canonical derivative engine differs from model')
            needed = {(r['name'], r['difficulty']) for r in pending}
            feet = [r for r in json.loads(derivative_file.read_text()) if (r['name'], r['difficulty']) in needed]
            for record in feet:
                raw = (args.input/'steps'/f"{record['name']}.json").read_bytes()
                if hashlib.sha256(raw).hexdigest() != record['source_sha256']:
                    raise ValueError('Stale canonical footing derivatives')
            keys = {(r['name'], r['difficulty']) for r in feet}
            if any((r['name'], r['difficulty']) not in keys for r in pending):
                raise ValueError('Canonical derivatives do not cover the requested charts')
            for record in feet:
                p = assets/'patterns'/f"{record['name']}.json"
                data = json.loads(p.read_text()) if p.exists() else {'sp': {}}
                data['sp'][record['difficulty']] = record['patterns']
                atomic_json(p, data)
            with ProcessPoolExecutor(max_workers=args.jobs, initializer=init_worker,
                                     initargs=(args.bundle, work, feet)) as pool:
                for i, (key, value, error) in enumerate(pool.map(predict_chart, pending), 1):
                    if error is None:
                        results[key] = value
                        atomic_json(args.cache/f"{value['input_hash']}.json", value)
                    else:
                        failures.append(dict(name=key[0], difficulty=key[1], reason=error))
                    if i % 100 == 0:
                        print(f'Scored {i}/{len(pending)}', flush=True)
    # Do not remove an existing rating when input analysis fails.
    lost = [(name, diff) for name, (_, song) in songs.items()
            for diff in song.get('scoring_tiers', {}).get('sp', {}) if (name, diff) not in results]
    inventory_file = args.cache/'coverage.json'
    inventory = json.loads(inventory_file.read_text()) if inventory_file.exists() else []
    expected = {tuple(key) for key in inventory}
    for name, diff in expected:
        if name in songs and songs[name][1].get('sp', {}).get(diff) is not None and (name, diff) not in results:
            lost.append((name, diff))
    lost = sorted(set(lost))
    report = dict(model=model, engine=engine, songs=len(songs), rated=len(results), failures=failures, lost=lost)
    atomic_json(args.report, report)
    if lost:
        raise ValueError(f'Coverage would drop for {len(lost)} previously rated charts; see {args.report}')
    for name, (path, song) in songs.items():
        entries = {d: results[(name, d)] for d in DIFFICULTIES if (name, d) in results}
        if entries:
            song['scoring_tiers'] = dict(schema=1, model=model, engine=engine, sp=entries)
        else:
            song.pop('scoring_tiers', None)
        atomic_json(path, song)
    atomic_json(inventory_file, sorted(expected | set(results)))
    checked = validate(args.input/'songs', args.input/'steps')
    if checked['problems']:
        raise ValueError(checked['problems'])
    print(json.dumps({**checked, 'report': str(args.report)}, indent=2))

if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--input', type=Path, required=True, help='Directory containing songs/ and steps/')
    p.add_argument('--bundle', type=Path, required=True)
    p.add_argument('--cache', type=Path, required=True)
    p.add_argument('--song', action='append', help='Exact song ID, repeat for a changed subset')
    p.add_argument('--report', type=Path, required=True)
    p.add_argument('--jobs', type=int, default=2, choices=range(1, 9))
    p.add_argument('--derivatives', type=Path, help='Pre-exported canonical derivatives for container inference')
    p.add_argument('--flutter', default='flutter')
    generate(p.parse_args())
