"""Offline inference using frozen references and chart-derived measurements."""
import bisect
import json
from functools import lru_cache
from pathlib import Path

import joblib
import numpy as np
import clean_timing
import features_v2
import learn
import native_rhythm
import passages
import rate
import scoring_features
import timing_features
import visibility_features
from fingerprint import tier_for


class Scorer:
    def __init__(self, bundle, root, feet):
        self.bundle, self.root = Path(bundle), Path(root)
        self.feet = {(c['name'], c['difficulty']): c for c in feet}
        self.manifest = json.loads((self.bundle/'manifest.json').read_text())
        # The feature extractors read only these explicit input directories.
        for module in (rate, learn, features_v2):
            module.ROOT = self.root
        self.context = {}

    @lru_cache(maxsize=16)
    def load(self, name):
        return joblib.load(self.bundle/name)

    def vector(self, name, diff, payload):
        key = (name, diff)
        if key not in self.context:
            self.context[key] = dict(song=json.loads((self.root/'assets/songs'/f'{name}.json').read_text()),
                                     notes=json.loads((self.root/'assets/steps'/f'{name}.json').read_text())['charts']['sp'][diff]['notes'])
        cached = self.context[key]
        song, notes = cached['song'], cached['notes']
        if 'features' not in cached:
            cached['features'] = {**learn.extract(rate.features(name, diff)), **features_v2.extra_features(name, diff)}
        f = cached['features']
        foot = self.feet[key]
        f.update(foot['features'])
        required = set(payload['features'])
        if any(k.startswith(('pad_mina_', 'feet_mina_')) for k in required) and 'native' not in cached:
            f.update(native_rhythm.evaluate(notes, foot['mina_rows'], self.bundle/self.manifest['native']))
            cached['native'] = True
        for prefix, sentinel, measure in (
            ('timing_', 'timing_weak_g1_r0.25_isolated', lambda: timing_features.calculate(notes)),
            ('visibility_', 'visibility_headline_bpm', lambda: visibility_features.calculate(song, notes, diff)),
            ('cleaned_', 'cleaned_bpm_max', lambda: clean_timing.calculate(name, diff, f, self.root)),
            ('scoring_', 'scoring_units', lambda: scoring_features.calculate(notes, f)),
            ('passage_', 'passage_0000', lambda: passages.calculate(song, notes, diff, foot['mina_rows'], self.bundle/'kernels.npz')),
        ):
            if any(k.startswith(prefix) for k in required) and sentinel not in f:
                f.update(measure())
        level = song['sp'][diff]
        raw = [f[k] for k in payload['features']]
        if not all(np.isfinite(raw)):
            raise ValueError('Non-finite chart features')
        ranks = []
        for k, value in zip(payload['features'], raw):
            values = payload['cdf'][str(level)][k]
            ranks.append((bisect.bisect_left(values, value)+bisect.bisect_right(values, value))/(2*len(values)))
        return np.array([raw+ranks+[level]]), level

    def predict(self, name, diff, model=None):
        payload = self.load(model or self.manifest['entry'])
        song = json.loads((self.root/'assets/songs'/f'{name}.json').read_text())
        level = song['sp'][diff]
        if 'level_models' in payload:
            position = self.predict(name, diff, payload['level_models'].get(str(level), payload['default_model']))['position']
        elif 'component_models' in payload:
            position = sum(part['weight']*self.predict(name, diff, part['path'])['position']
                           for part in payload['component_models'].values())
            cal = payload.get('calibrations', {}).get(str(level))
            strength = payload.get('calibration_strength', 0.)
            if cal:
                calibrated = (position*cal['coef']+cal['intercept'] if cal['kind']=='linear'
                              else float(np.interp(position, cal['x'], cal['y'])))
                position = (1-strength)*position+strength*calibrated
        else:
            x, level = self.vector(name, diff, payload)
            position = sum(m['weight']*float(m['model'].predict(x[:, m['column_indices']] if 'column_indices' in m else x)[0])
                           for m in payload['models'].values())
        return dict(tier=tier_for(level, position), position=position)
