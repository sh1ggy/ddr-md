"""Dependency-free canonical input identity, shared with publish validation."""
import hashlib
import json
import math

DIFFICULTIES = ('beginner', 'easy', 'medium', 'hard', 'challenge')
SCHEMA = 1


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False,
                      allow_nan=False).encode('utf-8')


def digest(value):
    return hashlib.sha256(canonical(value)).hexdigest()


def effective_timing(song, difficulty):
    index = 0
    if song.get('per_chart'):
        first = next(i for i, key in enumerate(DIFFICULTIES)
                     if song.get('sp', {}).get(key) is not None or
                     song.get('dp', {}).get(key) is not None)
        index = min(len(song['charts']) - 1, DIFFICULTIES.index(difficulty) - first)
    chart = song['charts'][index]
    return {key: chart[key] for key in ('bpms', 'stops')}


def input_hash(song, steps, difficulty, model, engine):
    return digest(dict(schema=SCHEMA, model=model, engine=engine, style='sp',
                       difficulty=difficulty, level=song['sp'][difficulty],
                       notes=steps['charts']['sp'][difficulty]['notes'],
                       timing=effective_timing(song, difficulty)))


def tier_for(level, position):
    if not 1 <= level <= 19 or not math.isfinite(position):
        raise ValueError('Unsupported level or non-finite position')
    step = .1 if level == 19 else .05
    return round(level + min(1-step, max(0, math.floor(position/step+1e-9)*step)), 2)
