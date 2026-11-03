"""Freeze a trusted fitted checkpoint into a relocatable, hash-checked bundle."""
import argparse
import hashlib
import json
import platform
import shutil
from pathlib import Path
import joblib
from fingerprint import canonical, digest

ROOT = Path(__file__).resolve().parents[2]


def source_hashes():
    paths = [ROOT/'tool/export_scoring_features.dart']
    paths += [ROOT/p for p in ('lib/models/parity.dart', 'lib/models/pattern_analysis.dart', 'lib/models/steps_model.dart')]
    paths += sorted((ROOT/'tool/scoring').glob('*.py'))
    paths += sorted(p for p in (ROOT/'tool/scoring/native').rglob('*') if p.is_file())
    return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}


def freeze(checkpoint, native, kernels, output, version):
    output.mkdir(parents=True, exist_ok=False)
    seen = {}
    def copy_model(path):
        path = path.resolve()
        if path in seen:
            return seen[path]
        name = path.name
        if name in seen.values():
            raise ValueError('Model filenames must be unique')
        seen[path] = name
        payload = joblib.load(path)
        for source, expected in payload.get('analysis_sources', {}).items():
            if source.startswith('lib/') and hashlib.sha256((ROOT/source).read_bytes()).hexdigest() != expected:
                raise ValueError(f'Fitted canonical engine differs: {source}')
        for key in list(payload):
            if key.endswith('_cache') or key in ('asset_root', 'analysis_sources', 'provider_sources', 'passage_params_path'):
                payload.pop(key)
        if 'component_models' in payload:
            for part in payload['component_models'].values():
                part['path'] = copy_model(Path(part['path']))
        if 'level_models' in payload:
            payload['level_models'] = {k: copy_model(Path(v)) for k, v in payload['level_models'].items()}
            payload['default_model'] = copy_model(Path(payload['default_model']))
        joblib.dump(payload, output/name, compress=3)
        return name
    entry = copy_model(checkpoint)
    native_name = 'libminacalc'+native.suffix
    shutil.copyfile(native, output/native_name)
    shutil.copyfile(kernels, output/'kernels.npz')
    hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(output.iterdir())}
    sources = source_hashes()
    manifest = dict(schema=1, model=version, entry=entry, native=native_name,
                    platform=platform.platform(), python='3.12', files=hashes,
                    sources=sources, engine=digest(dict(sources=sources, files=hashes)),
                    tier_steps={str(i): .1 if i==19 else .05 for i in range(1,20)})
    (output/'manifest.json').write_bytes(canonical(manifest)+b'\n')
    print(json.dumps(dict(bundle=str(output), engine=manifest['engine'], files=len(hashes))))

if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--checkpoint', required=True, type=Path)
    p.add_argument('--native', required=True, type=Path)
    p.add_argument('--kernels', required=True, type=Path)
    p.add_argument('--output', required=True, type=Path)
    p.add_argument('--version', default='scoring-v31')
    a = p.parse_args()
    freeze(a.checkpoint, a.native, a.kernels, a.output, a.version)
